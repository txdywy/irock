#include "irock_native_hysteria2_runtime.h"
#include "irock_hy2_internal.h"

#include <ngtcp2/ngtcp2.h>
#include <ngtcp2/ngtcp2_crypto.h>
#include <ngtcp2/ngtcp2_crypto_ossl.h>
#include <openssl/ssl.h>

#include <errno.h>
#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static void irock_hy2_rand(uint8_t *dest, size_t destlen, const ngtcp2_rand_ctx *rand_ctx) {
  (void)rand_ctx;
  arc4random_buf(dest, destlen);
}

static int irock_hy2_get_new_connection_id(ngtcp2_conn *conn, ngtcp2_cid *cid, ngtcp2_stateless_reset_token *token, size_t cidlen, void *user_data) {
  (void)conn;
  (void)user_data;

  uint8_t cid_bytes[NGTCP2_MAX_CIDLEN];
  arc4random_buf(cid_bytes, cidlen);
  ngtcp2_cid_init(cid, cid_bytes, cidlen);
  arc4random_buf(token->data, sizeof(token->data));
  return 0;
}

static int irock_hy2_get_path_challenge_data(ngtcp2_conn *conn, ngtcp2_path_challenge_data *data, void *user_data) {
  (void)conn;
  (void)user_data;

  arc4random_buf(data->data, sizeof(data->data));
  return 0;
}

static irock_hy2_result irock_hy2_session_enqueue_quic_datagram(struct irock_hy2_session *session, const uint8_t *bytes, int byte_count) {
  if (!session || byte_count < 0 || (byte_count > 0 && !bytes)) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_datagram *datagram = malloc(sizeof(struct irock_hy2_datagram));
  if (!datagram) {
    return IROCK_HY2_NETWORK_FAILED;
  }
  datagram->bytes = 0;
  datagram->length = byte_count;
  datagram->next = 0;
  if (byte_count > 0) {
    datagram->bytes = malloc((size_t)byte_count);
    if (!datagram->bytes) {
      free(datagram);
      return IROCK_HY2_NETWORK_FAILED;
    }
    memcpy(datagram->bytes, bytes, (size_t)byte_count);
  }
  if (session->datagram_tail) {
    session->datagram_tail->next = datagram;
  } else {
    session->datagram_head = datagram;
  }
  session->datagram_tail = datagram;
  return IROCK_HY2_OK;
}

static int irock_hy2_recv_datagram(ngtcp2_conn *conn, uint32_t flags, const uint8_t *data, size_t datalen, void *user_data) {
  (void)conn;
  (void)flags;
  irock_hy2_result result = irock_hy2_session_enqueue_quic_datagram(user_data, data, (int)datalen);
  return result == IROCK_HY2_OK ? 0 : NGTCP2_ERR_CALLBACK_FAILURE;
}

static int irock_hy2_recv_stream_data(ngtcp2_conn *conn, uint32_t flags, int64_t stream_id, uint64_t offset, const uint8_t *data, size_t datalen, void *user_data, void *stream_user_data) {
  (void)conn;
  (void)offset;
  (void)stream_user_data;

  struct irock_hy2_session *session = user_data;
  int consumed = 0;
  irock_hy2_result result;
  if (session && stream_id == session->auth_stream_id) {
    result = irock_hy2_session_receive_http3_stream_for_testing(session, stream_id, data, (int)datalen, flags & NGTCP2_STREAM_DATA_FLAG_FIN, &consumed);
  } else {
    result = irock_hy2_session_receive_tcp_stream_for_testing(session, stream_id, data, (int)datalen, flags & NGTCP2_STREAM_DATA_FLAG_FIN, &consumed);
  }
  return result == IROCK_HY2_OK ? 0 : NGTCP2_ERR_CALLBACK_FAILURE;
}

static ngtcp2_conn *irock_hy2_get_conn(ngtcp2_crypto_conn_ref *conn_ref) {
  struct irock_hy2_session *hy2_session = conn_ref ? conn_ref->user_data : 0;
  return hy2_session ? hy2_session->quic_conn : 0;
}

static ngtcp2_tstamp irock_hy2_timestamp(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (ngtcp2_tstamp)now.tv_sec * 1000000000 + (ngtcp2_tstamp)now.tv_nsec;
}

static irock_hy2_result irock_hy2_copy_connected_path(int fd, ngtcp2_path_storage *path_storage) {
  ngtcp2_path_storage_zero(path_storage);

  socklen_t local_length = sizeof(path_storage->local_addrbuf);
  if (getsockname(fd, (struct sockaddr *)&path_storage->local_addrbuf, &local_length) != 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  socklen_t remote_length = sizeof(path_storage->remote_addrbuf);
  if (getpeername(fd, (struct sockaddr *)&path_storage->remote_addrbuf, &remote_length) != 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  path_storage->path.local.addr = (ngtcp2_sockaddr *)&path_storage->local_addrbuf;
  path_storage->path.local.addrlen = local_length;
  path_storage->path.remote.addr = (ngtcp2_sockaddr *)&path_storage->remote_addrbuf;
  path_storage->path.remote.addrlen = remote_length;
  path_storage->path.user_data = 0;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_initialize_quic_for_testing(irock_hy2_session_ref session) {
  if (!session) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (hy2_session->udp_fd < 0 || !hy2_session->ssl || !hy2_session->crypto_ctx) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  ngtcp2_path_storage path_storage;
  irock_hy2_result path_result = irock_hy2_copy_connected_path(hy2_session->udp_fd, &path_storage);
  if (path_result != IROCK_HY2_OK) {
    return path_result;
  }

  uint8_t dcid_bytes[NGTCP2_MAX_CIDLEN];
  uint8_t scid_bytes[NGTCP2_MAX_CIDLEN];
  arc4random_buf(dcid_bytes, NGTCP2_MIN_INITIAL_DCIDLEN);
  arc4random_buf(scid_bytes, NGTCP2_MIN_INITIAL_DCIDLEN);
  ngtcp2_cid dcid;
  ngtcp2_cid scid;
  ngtcp2_cid_init(&dcid, dcid_bytes, NGTCP2_MIN_INITIAL_DCIDLEN);
  ngtcp2_cid_init(&scid, scid_bytes, NGTCP2_MIN_INITIAL_DCIDLEN);

  ngtcp2_callbacks callbacks;
  memset(&callbacks, 0, sizeof(callbacks));
  callbacks.client_initial = ngtcp2_crypto_client_initial_cb;
  callbacks.recv_crypto_data = ngtcp2_crypto_recv_crypto_data_cb;
  callbacks.encrypt = ngtcp2_crypto_encrypt_cb;
  callbacks.decrypt = ngtcp2_crypto_decrypt_cb;
  callbacks.hp_mask = ngtcp2_crypto_hp_mask_cb;
  callbacks.recv_retry = ngtcp2_crypto_recv_retry_cb;
  callbacks.recv_stream_data = irock_hy2_recv_stream_data;
  callbacks.recv_datagram = irock_hy2_recv_datagram;
  callbacks.rand = irock_hy2_rand;
  callbacks.update_key = ngtcp2_crypto_update_key_cb;
  callbacks.delete_crypto_aead_ctx = ngtcp2_crypto_delete_crypto_aead_ctx_cb;
  callbacks.delete_crypto_cipher_ctx = ngtcp2_crypto_delete_crypto_cipher_ctx_cb;
  callbacks.get_new_connection_id2 = irock_hy2_get_new_connection_id;
  callbacks.get_path_challenge_data2 = irock_hy2_get_path_challenge_data;

  ngtcp2_settings settings;
  ngtcp2_settings_default(&settings);
  ngtcp2_transport_params params;
  ngtcp2_transport_params_default(&params);
  params.initial_max_data = 1024 * 1024;
  params.initial_max_stream_data_bidi_local = 256 * 1024;
  params.initial_max_stream_data_bidi_remote = 256 * 1024;
  params.initial_max_streams_bidi = 100;
  params.initial_max_streams_uni = 3;
  params.max_datagram_frame_size = 65535;

  ngtcp2_conn *conn = 0;
  int result = ngtcp2_conn_client_new(&conn, &dcid, &scid, &path_storage.path, NGTCP2_PROTO_VER_V1, &callbacks, &settings, &params, 0, hy2_session);
  if (result != 0 || !conn) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  ngtcp2_crypto_conn_ref *conn_ref = malloc(sizeof(ngtcp2_crypto_conn_ref));
  if (!conn_ref) {
    ngtcp2_conn_del(conn);
    return IROCK_HY2_NETWORK_FAILED;
  }
  conn_ref->get_conn = irock_hy2_get_conn;
  conn_ref->user_data = hy2_session;

  ngtcp2_conn_set_tls_native_handle(conn, hy2_session->crypto_ctx);
  SSL_set_app_data(hy2_session->ssl, conn_ref);
  if (hy2_session->quic_conn) {
    ngtcp2_conn_del(hy2_session->quic_conn);
  }
  free(hy2_session->conn_ref);
  hy2_session->quic_conn = conn;
  hy2_session->conn_ref = conn_ref;
  hy2_session->has_quic_path = 1;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_copy_quic_state_for_testing(irock_hy2_session_ref session, int *has_connection, int *has_path, int *uses_version_1) {
  if (!session || !has_connection || !has_path || !uses_version_1) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  *has_connection = hy2_session->quic_conn ? 1 : 0;
  *has_path = hy2_session->has_quic_path;
  *uses_version_1 = hy2_session->quic_conn && ngtcp2_conn_get_client_chosen_version(hy2_session->quic_conn) == NGTCP2_PROTO_VER_V1 ? 1 : 0;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_write_quic_initial_for_testing(irock_hy2_session_ref session, int *bytes_written) {
  if (bytes_written) {
    *bytes_written = 0;
  }
  if (!session || !bytes_written) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (hy2_session->udp_fd < 0 || !hy2_session->quic_conn) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  ngtcp2_path_storage path_storage;
  irock_hy2_result path_result = irock_hy2_copy_connected_path(hy2_session->udp_fd, &path_storage);
  if (path_result != IROCK_HY2_OK) {
    return path_result;
  }

  uint8_t packet[NGTCP2_MAX_UDP_PAYLOAD_SIZE];
  ngtcp2_pkt_info packet_info;
  memset(&packet_info, 0, sizeof(packet_info));
  ngtcp2_ssize packet_length = ngtcp2_conn_write_pkt(hy2_session->quic_conn, &path_storage.path, &packet_info, packet, sizeof(packet), irock_hy2_timestamp());
  if (packet_length == 0) {
    return IROCK_HY2_BLOCKED;
  }
  if (packet_length < 0) {
    irock_hy2_set_last_error_for_testing("quic_write", (int)packet_length);
    return IROCK_HY2_NETWORK_FAILED;
  }

  ssize_t sent_length = send(hy2_session->udp_fd, packet, (size_t)packet_length, 0);
  if (sent_length != packet_length) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  hy2_session->last_quic_bytes_written = (int)sent_length;
  *bytes_written = hy2_session->last_quic_bytes_written;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_send_quic_datagram(irock_hy2_session_ref session, const uint8_t *bytes, int byte_count, int *bytes_written) {
  if (bytes_written) {
    *bytes_written = 0;
  }
  if (!session || !bytes_written || byte_count < 0 || (byte_count > 0 && !bytes)) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (hy2_session->udp_fd < 0 || !hy2_session->quic_conn) {
    return IROCK_HY2_BLOCKED;
  }

  ngtcp2_path_storage path_storage;
  irock_hy2_result path_result = irock_hy2_copy_connected_path(hy2_session->udp_fd, &path_storage);
  if (path_result != IROCK_HY2_OK) {
    return path_result;
  }

  uint8_t packet[NGTCP2_MAX_UDP_PAYLOAD_SIZE];
  ngtcp2_pkt_info packet_info;
  memset(&packet_info, 0, sizeof(packet_info));
  int accepted = 0;
  ngtcp2_ssize packet_length = ngtcp2_conn_write_datagram(
    hy2_session->quic_conn,
    &path_storage.path,
    &packet_info,
    packet,
    sizeof(packet),
    &accepted,
    NGTCP2_WRITE_DATAGRAM_FLAG_NONE,
    hy2_session->next_datagram_id++,
    bytes,
    (size_t)byte_count,
    irock_hy2_timestamp()
  );
  if (packet_length == 0 || !accepted) {
    return IROCK_HY2_BLOCKED;
  }
  if (packet_length < 0) {
    irock_hy2_set_last_error_for_testing("quic_datagram_write", (int)packet_length);
    return IROCK_HY2_NETWORK_FAILED;
  }

  ssize_t sent_length = send(hy2_session->udp_fd, packet, (size_t)packet_length, 0);
  if (sent_length != packet_length) {
    return IROCK_HY2_NETWORK_FAILED;
  }
  *bytes_written = byte_count;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_receive_quic_datagram(irock_hy2_session_ref session, uint8_t *buffer, int buffer_length, int *bytes_read) {
  if (bytes_read) {
    *bytes_read = 0;
  }
  if (!session || !buffer || buffer_length <= 0 || !bytes_read) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (!hy2_session->datagram_head) {
    return IROCK_HY2_BLOCKED;
  }
  struct irock_hy2_datagram *datagram = hy2_session->datagram_head;
  if (datagram->length > buffer_length) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }
  if (datagram->length > 0) {
    memcpy(buffer, datagram->bytes, (size_t)datagram->length);
  }
  *bytes_read = datagram->length;
  hy2_session->datagram_head = datagram->next;
  if (!hy2_session->datagram_head) {
    hy2_session->datagram_tail = 0;
  }
  free(datagram->bytes);
  free(datagram);
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_receive_quic_datagram_for_testing(irock_hy2_session_ref session, const uint8_t *bytes, int byte_count) {
  return irock_hy2_session_enqueue_quic_datagram(session, bytes, byte_count);
}

irock_hy2_result irock_hy2_session_receive_quic_for_testing(irock_hy2_session_ref session, int *packets_read) {
  if (packets_read) {
    *packets_read = 0;
  }
  if (!session || !packets_read) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (hy2_session->udp_fd < 0 || !hy2_session->quic_conn) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  uint8_t packet[65536];
  ssize_t received_length = recv(hy2_session->udp_fd, packet, sizeof(packet), 0);
  if (received_length < 0) {
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      return IROCK_HY2_BLOCKED;
    }
    return IROCK_HY2_NETWORK_FAILED;
  }
  if (received_length == 0) {
    return IROCK_HY2_BLOCKED;
  }

  ngtcp2_path_storage path_storage;
  irock_hy2_result path_result = irock_hy2_copy_connected_path(hy2_session->udp_fd, &path_storage);
  if (path_result != IROCK_HY2_OK) {
    return path_result;
  }

  ngtcp2_pkt_info packet_info;
  memset(&packet_info, 0, sizeof(packet_info));
  int result = ngtcp2_conn_read_pkt(hy2_session->quic_conn, &path_storage.path, &packet_info, packet, (size_t)received_length, irock_hy2_timestamp());
  if (result != 0) {
    irock_hy2_set_last_error_for_testing("quic_read", result);
    return IROCK_HY2_NETWORK_FAILED;
  }

  *packets_read = 1;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_step_quic_handshake_for_testing(irock_hy2_session_ref session, int *bytes_written, int *packets_read, int *handshake_completed) {
  if (bytes_written) {
    *bytes_written = 0;
  }
  if (packets_read) {
    *packets_read = 0;
  }
  if (handshake_completed) {
    *handshake_completed = 0;
  }
  if (!session || !bytes_written || !packets_read || !handshake_completed) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (hy2_session->udp_fd < 0 || !hy2_session->quic_conn) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  int local_bytes_written = 0;
  irock_hy2_result write_result = irock_hy2_session_write_quic_initial_for_testing(session, &local_bytes_written);
  if (write_result != IROCK_HY2_OK) {
    return write_result;
  }

  int local_packets_read = 0;
  irock_hy2_result read_result = irock_hy2_session_receive_quic_for_testing(session, &local_packets_read);
  *bytes_written = local_bytes_written;
  *packets_read = local_packets_read;
  *handshake_completed = ngtcp2_conn_get_handshake_completed(hy2_session->quic_conn) ? 1 : 0;
  if (*handshake_completed) {
    return IROCK_HY2_OK;
  }
  if (read_result == IROCK_HY2_BLOCKED) {
    return IROCK_HY2_BLOCKED;
  }
  return read_result;
}

irock_hy2_result irock_hy2_session_run_quic_handshake_for_testing(irock_hy2_session_ref session, int max_steps, int *bytes_written, int *packets_read, int *handshake_completed) {
  if (bytes_written) {
    *bytes_written = 0;
  }
  if (packets_read) {
    *packets_read = 0;
  }
  if (handshake_completed) {
    *handshake_completed = 0;
  }
  if (!session || max_steps <= 0 || !bytes_written || !packets_read || !handshake_completed) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  irock_hy2_result last_result = IROCK_HY2_BLOCKED;
  for (int step = 0; step < max_steps; step++) {
    int step_bytes_written = 0;
    int step_packets_read = 0;
    int step_handshake_completed = 0;
    last_result = irock_hy2_session_step_quic_handshake_for_testing(session, &step_bytes_written, &step_packets_read, &step_handshake_completed);
    *bytes_written += step_bytes_written;
    *packets_read += step_packets_read;
    *handshake_completed = step_handshake_completed;
    if (last_result == IROCK_HY2_OK || last_result != IROCK_HY2_BLOCKED || step_handshake_completed || step_packets_read == 0) {
      return last_result;
    }
  }

  return IROCK_HY2_BLOCKED;
}

irock_hy2_result irock_hy2_session_run_quic_handshake_until_blocked_for_testing(irock_hy2_session_ref session, int max_steps, int timeout_milliseconds, int *bytes_written, int *packets_read, int *handshake_completed) {
  if (bytes_written) {
    *bytes_written = 0;
  }
  if (packets_read) {
    *packets_read = 0;
  }
  if (handshake_completed) {
    *handshake_completed = 0;
  }
  if (!session || max_steps <= 0 || timeout_milliseconds < 0 || !bytes_written || !packets_read || !handshake_completed) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (hy2_session->udp_fd < 0 || !hy2_session->quic_conn) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  for (int step = 0; step < max_steps; step++) {
    int step_bytes_written = 0;
    irock_hy2_result write_result = irock_hy2_session_write_quic_initial_for_testing(session, &step_bytes_written);
    if (write_result != IROCK_HY2_OK && write_result != IROCK_HY2_BLOCKED) {
      return write_result;
    }
    *bytes_written += step_bytes_written;

    struct pollfd poll_fd;
    poll_fd.fd = hy2_session->udp_fd;
    poll_fd.events = POLLIN;
    poll_fd.revents = 0;
    int poll_result = poll(&poll_fd, 1, timeout_milliseconds);
    if (poll_result < 0) {
      return IROCK_HY2_NETWORK_FAILED;
    }
    if (poll_result == 0 || !(poll_fd.revents & POLLIN)) {
      continue;
    }

    int step_packets_read = 0;
    irock_hy2_result read_result = irock_hy2_session_receive_quic_for_testing(session, &step_packets_read);
    *packets_read += step_packets_read;
    *handshake_completed = ngtcp2_conn_get_handshake_completed(hy2_session->quic_conn) ? 1 : 0;
    if (*handshake_completed) {
      return irock_hy2_session_validate_peer_certificate_pin_for_testing(session);
    }
    if (read_result != IROCK_HY2_OK) {
      return read_result;
    }
  }

  return IROCK_HY2_BLOCKED;
}
