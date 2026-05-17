#ifndef IROCK_NATIVE_HYSTERIA2_RUNTIME_H
#define IROCK_NATIVE_HYSTERIA2_RUNTIME_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum irock_hy2_result {
  IROCK_HY2_OK = 0,
  IROCK_HY2_UNSUPPORTED = 1,
  IROCK_HY2_INVALID_CONFIGURATION = 2,
  IROCK_HY2_AUTH_FAILED = 3,
  IROCK_HY2_NETWORK_FAILED = 4,
  IROCK_HY2_BLOCKED = 5
} irock_hy2_result;

typedef struct irock_hy2_client_config {
  const char *server_host;
  uint16_t server_port;
  const char *server_name;
  const char *alpn;
  int allow_insecure;
  const char *certificate_pin_sha256;
} irock_hy2_client_config;

typedef void *irock_hy2_session_ref;
typedef void *irock_hy2_stream_ref;

irock_hy2_result irock_hy2_connect(const irock_hy2_client_config *config, const char *authentication, irock_hy2_session_ref *session);

irock_hy2_result irock_hy2_connect_with_connected_udp_socket(const irock_hy2_client_config *config, const char *authentication, int udp_fd, int remote_port, irock_hy2_session_ref *session);

irock_hy2_result irock_hy2_connect_quic_session(const irock_hy2_client_config *config, irock_hy2_session_ref *session);

void irock_hy2_set_last_error_for_testing(const char *stage, int code);

int irock_hy2_copy_last_error_for_testing(char *stage_buffer, int stage_buffer_length, int *code);

irock_hy2_result irock_hy2_session_create_for_testing(int authenticated, irock_hy2_session_ref *session);

irock_hy2_result irock_hy2_session_create_configured_for_testing(const irock_hy2_client_config *config, const char *authentication, int authenticated, irock_hy2_session_ref *session);

irock_hy2_result irock_hy2_session_copy_config_for_testing(
  irock_hy2_session_ref session,
  char *host_buffer,
  int host_buffer_length,
  int *server_port,
  char *server_name_buffer,
  int server_name_buffer_length,
  char *alpn_buffer,
  int alpn_buffer_length,
  char *certificate_pin_buffer,
  int certificate_pin_buffer_length,
  int *allow_insecure,
  int *authentication_stored
);

irock_hy2_result irock_hy2_session_initialize_tls_for_testing(irock_hy2_session_ref session);

irock_hy2_result irock_hy2_session_copy_tls_state_for_testing(
  irock_hy2_session_ref session,
  int *has_ssl_context,
  int *has_ssl,
  int *has_crypto_context,
  int *client_session_configured
);

// Validate base64(SHA256(DER certificate)) against a Hysteria2 pin.
irock_hy2_result irock_hy2_validate_certificate_pin_for_testing(const uint8_t *certificate_bytes, int certificate_byte_count, const char *certificate_pin_sha256);

irock_hy2_result irock_hy2_session_validate_peer_certificate_pin_for_testing(irock_hy2_session_ref session);

irock_hy2_result irock_hy2_session_initialize_udp_for_testing(irock_hy2_session_ref session);

irock_hy2_result irock_hy2_session_use_connected_udp_socket_for_testing(irock_hy2_session_ref session, int udp_fd, int remote_port);

irock_hy2_result irock_hy2_session_copy_udp_state_for_testing(irock_hy2_session_ref session, int *has_socket, int *remote_port);

irock_hy2_result irock_hy2_session_initialize_quic_for_testing(irock_hy2_session_ref session);

irock_hy2_result irock_hy2_session_copy_quic_state_for_testing(irock_hy2_session_ref session, int *has_connection, int *has_path, int *uses_version_1);

irock_hy2_result irock_hy2_session_write_quic_initial_for_testing(irock_hy2_session_ref session, int *bytes_written);

irock_hy2_result irock_hy2_session_receive_quic_for_testing(irock_hy2_session_ref session, int *packets_read);

irock_hy2_result irock_hy2_session_step_quic_handshake_for_testing(irock_hy2_session_ref session, int *bytes_written, int *packets_read, int *handshake_completed);

irock_hy2_result irock_hy2_session_run_quic_handshake_for_testing(irock_hy2_session_ref session, int max_steps, int *bytes_written, int *packets_read, int *handshake_completed);

irock_hy2_result irock_hy2_session_run_quic_handshake_until_blocked_for_testing(irock_hy2_session_ref session, int max_steps, int timeout_milliseconds, int *bytes_written, int *packets_read, int *handshake_completed);

irock_hy2_result irock_hy2_session_initialize_http3_for_testing(irock_hy2_session_ref session);

irock_hy2_result irock_hy2_session_copy_http3_state_for_testing(irock_hy2_session_ref session, int *has_http3_connection);

irock_hy2_result irock_hy2_session_submit_http3_auth_for_testing(irock_hy2_session_ref session, const char *authentication, int receive_mbps);

irock_hy2_result irock_hy2_session_copy_http3_auth_state_for_testing(irock_hy2_session_ref session, int64_t *auth_stream_id, int *auth_status, int *authentication_stored);

irock_hy2_result irock_hy2_session_apply_http3_auth_status_for_testing(irock_hy2_session_ref session, int status_code);

irock_hy2_result irock_hy2_session_receive_http3_header_for_testing(irock_hy2_session_ref session, int64_t stream_id, const char *name, const char *value);

irock_hy2_result irock_hy2_session_receive_http3_stream_for_testing(irock_hy2_session_ref session, int64_t stream_id, const uint8_t *bytes, int byte_count, int fin, int *bytes_consumed);

irock_hy2_result irock_hy2_session_copy_next_http3_write_for_testing(irock_hy2_session_ref session, int64_t *stream_id, int *bytes_available, int *fin);

irock_hy2_result irock_hy2_session_write_next_http3_for_testing(irock_hy2_session_ref session, int64_t *stream_id, int *bytes_written, int *bytes_accepted);

irock_hy2_result irock_hy2_session_run_http3_auth_for_testing(irock_hy2_session_ref session, int max_steps, int timeout_milliseconds, int *bytes_written, int *packets_read, int *auth_status);

irock_hy2_result irock_hy2_session_apply_auth_status(irock_hy2_session_ref session, int status_code);

irock_hy2_result irock_hy2_session_open_tcp_stream(irock_hy2_session_ref session, const char *address, irock_hy2_stream_ref *stream);

irock_hy2_result irock_hy2_session_export_keying_material(irock_hy2_session_ref session, const uint8_t *label, int label_length, const uint8_t *context, int context_length, uint8_t *output, int output_length);

irock_hy2_result irock_hy2_session_open_raw_quic_stream(irock_hy2_session_ref session, int bidirectional, const uint8_t *initial_payload, int initial_payload_length, irock_hy2_stream_ref *stream);

irock_hy2_result irock_hy2_session_send_quic_datagram(irock_hy2_session_ref session, const uint8_t *bytes, int byte_count, int *bytes_written);

irock_hy2_result irock_hy2_session_receive_quic_datagram(irock_hy2_session_ref session, uint8_t *buffer, int buffer_length, int *bytes_read);

irock_hy2_result irock_hy2_session_receive_quic_datagram_for_testing(irock_hy2_session_ref session, const uint8_t *bytes, int byte_count);

irock_hy2_result irock_hy2_session_create_tcp_stream_for_testing(irock_hy2_session_ref session, int64_t stream_id, irock_hy2_stream_ref *stream);

irock_hy2_result irock_hy2_session_create_raw_quic_stream_for_testing(irock_hy2_session_ref session, int64_t stream_id, const uint8_t *initial_payload, int initial_payload_length, irock_hy2_stream_ref *stream);

irock_hy2_result irock_hy2_session_receive_tcp_stream_for_testing(irock_hy2_session_ref session, int64_t stream_id, const uint8_t *bytes, int byte_count, int fin, int *bytes_consumed);

irock_hy2_result irock_hy2_stream_copy_state_for_testing(irock_hy2_stream_ref stream, int64_t *stream_id, int *request_bytes_written);

irock_hy2_result irock_hy2_stream_copy_write_state_for_testing(irock_hy2_stream_ref stream, int *request_bytes_sent);

irock_hy2_result irock_hy2_encode_tcp_request(const char *address, uint8_t *buffer, int buffer_length, int *bytes_written);

irock_hy2_result irock_hy2_validate_auth_status(int status_code);

irock_hy2_result irock_hy2_build_auth_request(
  const irock_hy2_client_config *config,
  const char *authentication,
  int receive_mbps,
  char *method_buffer,
  int method_buffer_length,
  char *path_buffer,
  int path_buffer_length,
  char *authority_buffer,
  int authority_buffer_length,
  int *auth_present,
  int *auth_length,
  int *resolved_receive_mbps
);

irock_hy2_result irock_hy2_build_auth_header_metadata(
  const irock_hy2_client_config *config,
  const char *authentication,
  int receive_mbps,
  int *header_count,
  int *auth_header_index,
  int *auth_header_value_length,
  char *cc_rx_buffer,
  int cc_rx_buffer_length
);

irock_hy2_result irock_hy2_stream_read(irock_hy2_stream_ref stream, uint8_t *buffer, int buffer_length, int *bytes_read);

irock_hy2_result irock_hy2_stream_write(irock_hy2_stream_ref stream, const uint8_t *bytes, int byte_count);

irock_hy2_result irock_hy2_stream_close_write(irock_hy2_stream_ref stream);

void irock_hy2_stream_free(irock_hy2_stream_ref stream);

void irock_hy2_session_free(irock_hy2_session_ref session);

#ifdef __cplusplus
}
#endif

#endif
