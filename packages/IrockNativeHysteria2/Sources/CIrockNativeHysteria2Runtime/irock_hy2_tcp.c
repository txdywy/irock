#include "irock_native_hysteria2_runtime.h"
#include "irock_hy2_internal.h"

#include <ngtcp2/ngtcp2.h>

#include <stdlib.h>
#include <string.h>

static struct irock_hy2_stream *irock_hy2_create_stream(struct irock_hy2_session *session, int64_t stream_id, const uint8_t *request_bytes, int request_bytes_written) {
  struct irock_hy2_stream *stream = malloc(sizeof(struct irock_hy2_stream));
  if (!stream) {
    return 0;
  }
  stream->session = session;
  stream->stream_id = stream_id;
  stream->request_bytes_written = request_bytes_written;
  if (request_bytes_written > 0 && request_bytes) {
    memcpy(stream->request_bytes, request_bytes, (size_t)request_bytes_written);
  }
  stream->request_bytes_sent = 0;
  stream->read_buffer = 0;
  stream->read_buffer_length = 0;
  stream->read_buffer_capacity = 0;
  stream->write_buffer = 0;
  stream->write_buffer_length = 0;
  stream->write_buffer_sent = 0;
  stream->read_closed = 0;
  stream->next = 0;
  return stream;
}

irock_hy2_result irock_hy2_session_open_tcp_stream(irock_hy2_session_ref session, const char *address, irock_hy2_stream_ref *stream) {
  if (stream) {
    *stream = 0;
  }

  if (!session || !address || !address[0]) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }
  struct irock_hy2_session *hy2_session = session;
  if (!hy2_session->authenticated) {
    return IROCK_HY2_AUTH_FAILED;
  }
  if (!hy2_session->quic_conn) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  uint8_t request_buffer[256];
  int request_bytes_written = 0;
  irock_hy2_result encode_result = irock_hy2_encode_tcp_request(address, request_buffer, sizeof(request_buffer), &request_bytes_written);
  if (encode_result != IROCK_HY2_OK) {
    return encode_result;
  }

  int64_t stream_id = -1;
  int open_result = ngtcp2_conn_open_bidi_stream(hy2_session->quic_conn, &stream_id, 0);
  if (open_result == NGTCP2_ERR_INVALID_STATE || open_result == NGTCP2_ERR_STREAM_ID_BLOCKED) {
    return IROCK_HY2_BLOCKED;
  }
  if (open_result != 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  struct irock_hy2_stream *created_stream = irock_hy2_create_stream(hy2_session, stream_id, request_buffer, request_bytes_written);
  if (!created_stream) {
    return IROCK_HY2_NETWORK_FAILED;
  }
  irock_hy2_result register_result = irock_hy2_session_register_stream(hy2_session, created_stream);
  if (register_result != IROCK_HY2_OK) {
    irock_hy2_stream_release(created_stream);
    free(created_stream);
    return register_result;
  }
  *stream = created_stream;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_create_tcp_stream_for_testing(irock_hy2_session_ref session, int64_t stream_id, irock_hy2_stream_ref *stream) {
  if (stream) {
    *stream = 0;
  }
  if (!session || stream_id < 0 || !stream) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  struct irock_hy2_stream *created_stream = irock_hy2_create_stream(hy2_session, stream_id, 0, 0);
  if (!created_stream) {
    return IROCK_HY2_NETWORK_FAILED;
  }
  irock_hy2_result register_result = irock_hy2_session_register_stream(hy2_session, created_stream);
  if (register_result != IROCK_HY2_OK) {
    irock_hy2_stream_release(created_stream);
    free(created_stream);
    return register_result;
  }

  *stream = created_stream;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_encode_tcp_request(const char *address, uint8_t *buffer, int buffer_length, int *bytes_written) {
  if (bytes_written) {
    *bytes_written = 0;
  }

  if (!address || !address[0] || !buffer || buffer_length <= 0 || !bytes_written) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  size_t address_length = strlen(address);
  if (address_length >= 0x40 || buffer_length < (int)(3 + address_length + 1)) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  buffer[0] = 0x44;
  buffer[1] = 0x01;
  buffer[2] = (uint8_t)address_length;
  memcpy(buffer + 3, address, address_length);
  buffer[3 + address_length] = 0x00;
  *bytes_written = (int)(3 + address_length + 1);
  return IROCK_HY2_OK;
}
