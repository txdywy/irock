#include "irock_native_hysteria2_runtime.h"

#include <stdio.h>
#include <string.h>

static int irock_hy2_copy_c_string(char *buffer, int buffer_length, const char *value) {
  size_t value_length = strlen(value);
  if (!buffer || buffer_length <= 0 || value_length >= (size_t)buffer_length) {
    return 0;
  }

  memcpy(buffer, value, value_length + 1);
  return 1;
}

irock_hy2_result irock_hy2_validate_auth_status(int status_code) {
  if (status_code <= 0) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  return status_code == 233 ? IROCK_HY2_OK : IROCK_HY2_AUTH_FAILED;
}

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
) {
  if (auth_present) {
    *auth_present = 0;
  }
  if (auth_length) {
    *auth_length = 0;
  }
  if (resolved_receive_mbps) {
    *resolved_receive_mbps = 0;
  }

  if (!config || !config->server_name || !config->server_name[0] || !authentication || !authentication[0] || !auth_present || !auth_length || !resolved_receive_mbps) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }
  if (!irock_hy2_copy_c_string(method_buffer, method_buffer_length, "POST") || !irock_hy2_copy_c_string(path_buffer, path_buffer_length, "/auth") || !irock_hy2_copy_c_string(authority_buffer, authority_buffer_length, config->server_name)) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  *auth_present = 1;
  *auth_length = (int)strlen(authentication);
  *resolved_receive_mbps = receive_mbps > 0 ? receive_mbps : 1;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_build_auth_header_metadata(
  const irock_hy2_client_config *config,
  const char *authentication,
  int receive_mbps,
  int *header_count,
  int *auth_header_index,
  int *auth_header_value_length,
  char *cc_rx_buffer,
  int cc_rx_buffer_length
) {
  if (header_count) {
    *header_count = 0;
  }
  if (auth_header_index) {
    *auth_header_index = 0;
  }
  if (auth_header_value_length) {
    *auth_header_value_length = 0;
  }

  if (!config || !config->server_name || !config->server_name[0] || !authentication || !authentication[0] || !header_count || !auth_header_index || !auth_header_value_length) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  char receive_mbps_text[16];
  int resolved_receive_mbps = receive_mbps > 0 ? receive_mbps : 1;
  int written = snprintf(receive_mbps_text, sizeof(receive_mbps_text), "%d", resolved_receive_mbps);
  if (written <= 0 || written >= (int)sizeof(receive_mbps_text) || !irock_hy2_copy_c_string(cc_rx_buffer, cc_rx_buffer_length, receive_mbps_text)) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  *header_count = 6;
  *auth_header_index = 4;
  *auth_header_value_length = (int)strlen(authentication);
  return IROCK_HY2_OK;
}
