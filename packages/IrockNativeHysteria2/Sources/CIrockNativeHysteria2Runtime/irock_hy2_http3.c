#include "irock_native_hysteria2_runtime.h"
#include "irock_hy2_internal.h"

#include <nghttp3/nghttp3.h>
#include <ngtcp2/ngtcp2.h>

#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static void irock_hy2_http3_rand(uint8_t *dest, size_t destlen) {
  arc4random_buf(dest, destlen);
}

static ngtcp2_tstamp irock_hy2_http3_timestamp(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (ngtcp2_tstamp)now.tv_sec * 1000000000 + (ngtcp2_tstamp)now.tv_nsec;
}

static irock_hy2_result irock_hy2_http3_copy_connected_path(int fd, ngtcp2_path_storage *path_storage) {
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

static int irock_hy2_http3_decimal_value(const uint8_t *value, size_t value_length) {
  if (!value || value_length == 0) {
    return 0;
  }

  int parsed = 0;
  for (size_t index = 0; index < value_length; index++) {
    if (value[index] < '0' || value[index] > '9') {
      return 0;
    }
    parsed = parsed * 10 + (value[index] - '0');
  }
  return parsed;
}

static irock_hy2_result irock_hy2_http3_apply_header(struct irock_hy2_session *session, int64_t stream_id, const uint8_t *name, size_t name_length, const uint8_t *value, size_t value_length) {
  if (!session || (session->auth_stream_id >= 0 && stream_id != session->auth_stream_id)) {
    return IROCK_HY2_OK;
  }
  if (name_length != 7 || memcmp(name, ":status", 7) != 0) {
    return IROCK_HY2_OK;
  }

  int status_code = irock_hy2_http3_decimal_value(value, value_length);
  session->auth_status = status_code;
  return irock_hy2_session_apply_auth_status(session, status_code);
}

static int irock_hy2_recv_header(nghttp3_conn *conn, int64_t stream_id, int32_t token, nghttp3_rcbuf *name, nghttp3_rcbuf *value, uint8_t flags, void *conn_user_data, void *stream_user_data) {
  (void)conn;
  (void)token;
  (void)flags;
  (void)stream_user_data;

  struct irock_hy2_session *session = conn_user_data;
  nghttp3_vec name_vector = nghttp3_rcbuf_get_buf(name);
  nghttp3_vec value_vector = nghttp3_rcbuf_get_buf(value);
  irock_hy2_result result = irock_hy2_http3_apply_header(session, stream_id, name_vector.base, name_vector.len, value_vector.base, value_vector.len);
  return result == IROCK_HY2_NETWORK_FAILED || result == IROCK_HY2_INVALID_CONFIGURATION ? NGHTTP3_ERR_CALLBACK_FAILURE : 0;
}

irock_hy2_result irock_hy2_session_initialize_http3_for_testing(irock_hy2_session_ref session) {
  if (!session) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (!hy2_session->quic_conn) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  nghttp3_callbacks callbacks;
  memset(&callbacks, 0, sizeof(callbacks));
  callbacks.recv_header = irock_hy2_recv_header;
  callbacks.rand = irock_hy2_http3_rand;

  nghttp3_settings settings;
  nghttp3_settings_default(&settings);

  nghttp3_conn *conn = 0;
  int result = nghttp3_conn_client_new(&conn, &callbacks, &settings, 0, hy2_session);
  if (result != 0 || !conn) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  if (hy2_session->http3_conn) {
    nghttp3_conn_del(hy2_session->http3_conn);
  }
  hy2_session->http3_conn = conn;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_copy_http3_state_for_testing(irock_hy2_session_ref session, int *has_http3_connection) {
  if (!session || !has_http3_connection) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  *has_http3_connection = hy2_session->http3_conn ? 1 : 0;
  return IROCK_HY2_OK;
}

static nghttp3_nv irock_hy2_header(const char *name, const char *value, uint8_t flags) {
  nghttp3_nv header;
  header.name = (const uint8_t *)name;
  header.value = (const uint8_t *)value;
  header.namelen = strlen(name);
  header.valuelen = strlen(value);
  header.flags = flags;
  return header;
}

irock_hy2_result irock_hy2_session_submit_http3_auth_for_testing(irock_hy2_session_ref session, const char *authentication, int receive_mbps) {
  if (!session || !authentication || !authentication[0] || receive_mbps <= 0) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (!hy2_session->http3_conn || !hy2_session->server_name || !hy2_session->server_name[0]) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  int64_t control_stream_id = 2;
  int64_t qpack_encoder_stream_id = 6;
  int64_t qpack_decoder_stream_id = 10;
  int64_t stream_id = 0;
  if (nghttp3_conn_bind_control_stream(hy2_session->http3_conn, control_stream_id) != 0 ||
      nghttp3_conn_bind_qpack_streams(hy2_session->http3_conn, qpack_encoder_stream_id, qpack_decoder_stream_id) != 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  char receive_mbps_text[16];
  snprintf(receive_mbps_text, sizeof(receive_mbps_text), "%d", receive_mbps);
  nghttp3_nv headers[] = {
    irock_hy2_header(":method", "POST", NGHTTP3_NV_FLAG_NONE),
    irock_hy2_header(":scheme", "https", NGHTTP3_NV_FLAG_NONE),
    irock_hy2_header(":path", "/auth", NGHTTP3_NV_FLAG_NONE),
    irock_hy2_header(":authority", hy2_session->server_name, NGHTTP3_NV_FLAG_NONE),
    irock_hy2_header("hysteria-auth", authentication, NGHTTP3_NV_FLAG_NEVER_INDEX),
    irock_hy2_header("hysteria-cc-rx", receive_mbps_text, NGHTTP3_NV_FLAG_NONE)
  };

  int result = nghttp3_conn_submit_request(hy2_session->http3_conn, stream_id, headers, sizeof(headers) / sizeof(headers[0]), 0, hy2_session);
  if (result != 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  hy2_session->auth_stream_id = stream_id;
  hy2_session->auth_status = 0;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_copy_http3_auth_state_for_testing(irock_hy2_session_ref session, int64_t *auth_stream_id, int *auth_status, int *authentication_stored) {
  if (!session || !auth_stream_id || !auth_status || !authentication_stored) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  *auth_stream_id = hy2_session->auth_stream_id;
  *auth_status = hy2_session->auth_status;
  *authentication_stored = 0;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_apply_http3_auth_status_for_testing(irock_hy2_session_ref session, int status_code) {
  if (!session) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  hy2_session->auth_status = status_code;
  return irock_hy2_session_apply_auth_status(session, status_code);
}

irock_hy2_result irock_hy2_session_receive_http3_header_for_testing(irock_hy2_session_ref session, int64_t stream_id, const char *name, const char *value) {
  if (!session || !name || !value) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  return irock_hy2_http3_apply_header(session, stream_id, (const uint8_t *)name, strlen(name), (const uint8_t *)value, strlen(value));
}

irock_hy2_result irock_hy2_session_receive_http3_stream_for_testing(irock_hy2_session_ref session, int64_t stream_id, const uint8_t *bytes, int byte_count, int fin, int *bytes_consumed) {
  if (bytes_consumed) {
    *bytes_consumed = 0;
  }
  if (!session || !bytes_consumed || byte_count < 0 || (byte_count > 0 && !bytes)) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (!hy2_session->http3_conn) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  nghttp3_ssize consumed = nghttp3_conn_read_stream(hy2_session->http3_conn, stream_id, bytes, (size_t)byte_count, fin ? 1 : 0);
  if (consumed < 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  *bytes_consumed = (int)consumed;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_copy_next_http3_write_for_testing(irock_hy2_session_ref session, int64_t *stream_id, int *bytes_available, int *fin) {
  if (!session || !stream_id || !bytes_available || !fin) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (!hy2_session->http3_conn) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  nghttp3_vec vectors[16];
  int local_fin = 0;
  int64_t local_stream_id = -1;
  nghttp3_ssize vector_count = nghttp3_conn_writev_stream(hy2_session->http3_conn, &local_stream_id, &local_fin, vectors, sizeof(vectors) / sizeof(vectors[0]));
  if (vector_count < 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  size_t total_length = 0;
  for (nghttp3_ssize index = 0; index < vector_count; index++) {
    total_length += vectors[index].len;
  }

  *stream_id = local_stream_id;
  *bytes_available = (int)total_length;
  *fin = local_fin;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_write_next_http3_for_testing(irock_hy2_session_ref session, int64_t *stream_id, int *bytes_written, int *bytes_accepted) {
  if (stream_id) {
    *stream_id = -1;
  }
  if (bytes_written) {
    *bytes_written = 0;
  }
  if (bytes_accepted) {
    *bytes_accepted = 0;
  }
  if (!session || !stream_id || !bytes_written || !bytes_accepted) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (hy2_session->udp_fd < 0 || !hy2_session->quic_conn || !hy2_session->http3_conn) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  nghttp3_vec http3_vectors[16];
  int fin = 0;
  int64_t local_stream_id = -1;
  nghttp3_ssize http3_vector_count = nghttp3_conn_writev_stream(hy2_session->http3_conn, &local_stream_id, &fin, http3_vectors, sizeof(http3_vectors) / sizeof(http3_vectors[0]));
  if (http3_vector_count < 0 || local_stream_id < 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }
  *stream_id = local_stream_id;
  if (!ngtcp2_conn_get_handshake_completed(hy2_session->quic_conn)) {
    return IROCK_HY2_BLOCKED;
  }

  ngtcp2_vec quic_vectors[16];
  for (nghttp3_ssize index = 0; index < http3_vector_count; index++) {
    quic_vectors[index].base = http3_vectors[index].base;
    quic_vectors[index].len = http3_vectors[index].len;
  }

  ngtcp2_path_storage path_storage;
  irock_hy2_result path_result = irock_hy2_http3_copy_connected_path(hy2_session->udp_fd, &path_storage);
  if (path_result != IROCK_HY2_OK) {
    return path_result;
  }

  uint8_t packet[NGTCP2_MAX_UDP_PAYLOAD_SIZE];
  ngtcp2_pkt_info packet_info;
  memset(&packet_info, 0, sizeof(packet_info));
  ngtcp2_ssize accepted_length = 0;
  ngtcp2_ssize packet_length = ngtcp2_conn_writev_stream(
    hy2_session->quic_conn,
    &path_storage.path,
    &packet_info,
    packet,
    sizeof(packet),
    &accepted_length,
    NGTCP2_WRITE_STREAM_FLAG_NONE,
    local_stream_id,
    quic_vectors,
    (size_t)http3_vector_count,
    irock_hy2_http3_timestamp()
  );
  *stream_id = local_stream_id;
  if (packet_length == 0 || accepted_length == 0 || packet_length == NGTCP2_ERR_INVALID_STATE || packet_length == NGTCP2_ERR_STREAM_DATA_BLOCKED) {
    return IROCK_HY2_BLOCKED;
  }
  if (packet_length < 0 || accepted_length < 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  ssize_t sent_length = send(hy2_session->udp_fd, packet, (size_t)packet_length, 0);
  if (sent_length != packet_length) {
    return IROCK_HY2_NETWORK_FAILED;
  }
  if (nghttp3_conn_add_write_offset(hy2_session->http3_conn, local_stream_id, (size_t)accepted_length) != 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  *stream_id = local_stream_id;
  *bytes_written = (int)sent_length;
  *bytes_accepted = (int)accepted_length;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_run_http3_auth_for_testing(irock_hy2_session_ref session, int max_steps, int timeout_milliseconds, int *bytes_written, int *packets_read, int *auth_status) {
  if (bytes_written) {
    *bytes_written = 0;
  }
  if (packets_read) {
    *packets_read = 0;
  }
  if (auth_status) {
    *auth_status = 0;
  }
  if (!session || max_steps <= 0 || timeout_milliseconds < 0 || !bytes_written || !packets_read || !auth_status) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (hy2_session->udp_fd < 0 || !hy2_session->quic_conn || !hy2_session->http3_conn) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }
  if (!ngtcp2_conn_get_handshake_completed(hy2_session->quic_conn)) {
    *auth_status = hy2_session->auth_status;
    return IROCK_HY2_BLOCKED;
  }

  for (int step = 0; step < max_steps; step++) {
    int64_t stream_id = -1;
    int step_bytes_written = 0;
    int bytes_accepted = 0;
    irock_hy2_result write_result = irock_hy2_session_write_next_http3_for_testing(session, &stream_id, &step_bytes_written, &bytes_accepted);
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
      *auth_status = hy2_session->auth_status;
      return hy2_session->auth_status == 233 ? IROCK_HY2_OK : IROCK_HY2_BLOCKED;
    }

    int step_packets_read = 0;
    irock_hy2_result read_result = irock_hy2_session_receive_quic_for_testing(session, &step_packets_read);
    *packets_read += step_packets_read;
    *auth_status = hy2_session->auth_status;
    if (hy2_session->auth_status == 233) {
      return IROCK_HY2_OK;
    }
    if (hy2_session->auth_status != 0) {
      return IROCK_HY2_AUTH_FAILED;
    }
    if (read_result != IROCK_HY2_OK) {
      return read_result;
    }
  }

  *auth_status = hy2_session->auth_status;
  return hy2_session->auth_status == 233 ? IROCK_HY2_OK : IROCK_HY2_BLOCKED;
}
