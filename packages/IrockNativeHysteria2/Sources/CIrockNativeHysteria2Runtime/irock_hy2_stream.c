#include "irock_native_hysteria2_runtime.h"
#include "irock_hy2_internal.h"

#include <ngtcp2/ngtcp2.h>

#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static ngtcp2_tstamp irock_hy2_stream_timestamp(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (ngtcp2_tstamp)now.tv_sec * 1000000000 + (ngtcp2_tstamp)now.tv_nsec;
}

static irock_hy2_result irock_hy2_stream_copy_connected_path(int fd, ngtcp2_path_storage *path_storage) {
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

struct irock_hy2_stream *irock_hy2_session_find_stream(struct irock_hy2_session *session, int64_t stream_id) {
  if (!session) {
    return 0;
  }

  struct irock_hy2_stream *stream = session->streams;
  while (stream) {
    if (stream->stream_id == stream_id) {
      return stream;
    }
    stream = stream->next;
  }
  return 0;
}

irock_hy2_result irock_hy2_session_register_stream(struct irock_hy2_session *session, struct irock_hy2_stream *stream) {
  if (!session || !stream || stream->stream_id < 0) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }
  if (irock_hy2_session_find_stream(session, stream->stream_id)) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  stream->session = session;
  stream->next = session->streams;
  session->streams = stream;
  return IROCK_HY2_OK;
}

void irock_hy2_session_unregister_stream(struct irock_hy2_session *session, struct irock_hy2_stream *stream) {
  if (!session || !stream) {
    return;
  }

  struct irock_hy2_stream **cursor = &session->streams;
  while (*cursor) {
    if (*cursor == stream) {
      *cursor = stream->next;
      stream->next = 0;
      return;
    }
    cursor = &(*cursor)->next;
  }
}

void irock_hy2_stream_release(struct irock_hy2_stream *stream) {
  if (!stream) {
    return;
  }

  free(stream->read_buffer);
  stream->read_buffer = 0;
  stream->read_buffer_length = 0;
  stream->read_buffer_capacity = 0;
}

irock_hy2_result irock_hy2_session_receive_tcp_stream_for_testing(irock_hy2_session_ref session, int64_t stream_id, const uint8_t *bytes, int byte_count, int fin, int *bytes_consumed) {
  if (bytes_consumed) {
    *bytes_consumed = 0;
  }
  if (!session || stream_id < 0 || byte_count < 0 || (byte_count > 0 && !bytes) || !bytes_consumed) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  struct irock_hy2_stream *stream = irock_hy2_session_find_stream(hy2_session, stream_id);
  if (!stream) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  if (byte_count > 0) {
    int required_capacity = stream->read_buffer_length + byte_count;
    if (required_capacity > stream->read_buffer_capacity) {
      int next_capacity = stream->read_buffer_capacity > 0 ? stream->read_buffer_capacity : 1024;
      while (next_capacity < required_capacity) {
        next_capacity *= 2;
      }
      uint8_t *next_buffer = realloc(stream->read_buffer, (size_t)next_capacity);
      if (!next_buffer) {
        return IROCK_HY2_NETWORK_FAILED;
      }
      stream->read_buffer = next_buffer;
      stream->read_buffer_capacity = next_capacity;
    }
    memcpy(stream->read_buffer + stream->read_buffer_length, bytes, (size_t)byte_count);
    stream->read_buffer_length += byte_count;
  }
  if (fin) {
    stream->read_closed = 1;
  }

  *bytes_consumed = byte_count;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_stream_copy_state_for_testing(irock_hy2_stream_ref stream, int64_t *stream_id, int *request_bytes_written) {
  if (!stream || !stream_id || !request_bytes_written) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_stream *hy2_stream = stream;
  *stream_id = hy2_stream->stream_id;
  *request_bytes_written = hy2_stream->request_bytes_written;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_stream_copy_write_state_for_testing(irock_hy2_stream_ref stream, int *request_bytes_sent) {
  if (!stream || !request_bytes_sent) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_stream *hy2_stream = stream;
  *request_bytes_sent = hy2_stream->request_bytes_sent;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_stream_read(irock_hy2_stream_ref stream, uint8_t *buffer, int buffer_length, int *bytes_read) {
  if (bytes_read) {
    *bytes_read = 0;
  }

  if (!stream || !buffer || buffer_length <= 0 || !bytes_read) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_stream *hy2_stream = stream;
  if (hy2_stream->read_buffer_length == 0) {
    return hy2_stream->read_closed ? IROCK_HY2_OK : IROCK_HY2_BLOCKED;
  }

  int readable_length = hy2_stream->read_buffer_length < buffer_length ? hy2_stream->read_buffer_length : buffer_length;
  memcpy(buffer, hy2_stream->read_buffer, (size_t)readable_length);
  int remaining_length = hy2_stream->read_buffer_length - readable_length;
  if (remaining_length > 0) {
    memmove(hy2_stream->read_buffer, hy2_stream->read_buffer + readable_length, (size_t)remaining_length);
  }
  hy2_stream->read_buffer_length = remaining_length;
  *bytes_read = readable_length;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_stream_write(irock_hy2_stream_ref stream, const uint8_t *bytes, int byte_count) {
  if (!stream || !bytes || byte_count < 0) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_stream *hy2_stream = stream;
  struct irock_hy2_session *hy2_session = hy2_stream->session;
  if (!hy2_session || hy2_session->udp_fd < 0 || !hy2_session->quic_conn) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  uint8_t packet[NGTCP2_MAX_UDP_PAYLOAD_SIZE];
  ngtcp2_pkt_info packet_info;
  memset(&packet_info, 0, sizeof(packet_info));
  ngtcp2_path_storage path_storage;
  irock_hy2_result path_result = irock_hy2_stream_copy_connected_path(hy2_session->udp_fd, &path_storage);
  if (path_result != IROCK_HY2_OK) {
    return path_result;
  }

  ngtcp2_vec vectors[2];
  size_t vector_count = 0;
  if (hy2_stream->request_bytes_sent < hy2_stream->request_bytes_written) {
    vectors[vector_count].base = hy2_stream->request_bytes + hy2_stream->request_bytes_sent;
    vectors[vector_count].len = (size_t)(hy2_stream->request_bytes_written - hy2_stream->request_bytes_sent);
    vector_count++;
  }
  if (byte_count > 0) {
    vectors[vector_count].base = (uint8_t *)bytes;
    vectors[vector_count].len = (size_t)byte_count;
    vector_count++;
  }
  if (vector_count == 0) {
    return IROCK_HY2_OK;
  }

  ngtcp2_ssize accepted_length = 0;
  ngtcp2_ssize packet_length = ngtcp2_conn_writev_stream(
    hy2_session->quic_conn,
    &path_storage.path,
    &packet_info,
    packet,
    sizeof(packet),
    &accepted_length,
    NGTCP2_WRITE_STREAM_FLAG_NONE,
    hy2_stream->stream_id,
    vectors,
    vector_count,
    irock_hy2_stream_timestamp()
  );
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
  if (hy2_stream->request_bytes_sent < hy2_stream->request_bytes_written) {
    int remaining_request_bytes = hy2_stream->request_bytes_written - hy2_stream->request_bytes_sent;
    int request_bytes_accepted = accepted_length > remaining_request_bytes ? remaining_request_bytes : (int)accepted_length;
    hy2_stream->request_bytes_sent += request_bytes_accepted;
  }
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_stream_close_write(irock_hy2_stream_ref stream) {
  if (!stream) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_stream *hy2_stream = stream;
  struct irock_hy2_session *hy2_session = hy2_stream->session;
  if (!hy2_session || hy2_session->udp_fd < 0 || !hy2_session->quic_conn) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  uint8_t packet[NGTCP2_MAX_UDP_PAYLOAD_SIZE];
  ngtcp2_pkt_info packet_info;
  memset(&packet_info, 0, sizeof(packet_info));
  ngtcp2_path_storage path_storage;
  irock_hy2_result path_result = irock_hy2_stream_copy_connected_path(hy2_session->udp_fd, &path_storage);
  if (path_result != IROCK_HY2_OK) {
    return path_result;
  }

  ngtcp2_ssize packet_length = ngtcp2_conn_write_stream(
    hy2_session->quic_conn,
    &path_storage.path,
    &packet_info,
    packet,
    sizeof(packet),
    0,
    NGTCP2_WRITE_STREAM_FLAG_FIN,
    hy2_stream->stream_id,
    0,
    0,
    irock_hy2_stream_timestamp()
  );
  if (packet_length == 0 || packet_length == NGTCP2_ERR_INVALID_STATE || packet_length == NGTCP2_ERR_STREAM_DATA_BLOCKED) {
    return IROCK_HY2_BLOCKED;
  }
  if (packet_length < 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  ssize_t sent_length = send(hy2_session->udp_fd, packet, (size_t)packet_length, 0);
  if (sent_length != packet_length) {
    return IROCK_HY2_NETWORK_FAILED;
  }
  return IROCK_HY2_OK;
}

void irock_hy2_stream_free(irock_hy2_stream_ref stream) {
  struct irock_hy2_stream *hy2_stream = stream;
  if (!hy2_stream) {
    return;
  }

  irock_hy2_session_unregister_stream(hy2_stream->session, hy2_stream);
  irock_hy2_stream_release(hy2_stream);
  free(hy2_stream);
}
