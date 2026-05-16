#include "irock_native_hysteria2_runtime.h"
#include "irock_hy2_internal.h"

#include <nghttp3/nghttp3.h>
#include <ngtcp2/ngtcp2.h>
#include <ngtcp2/ngtcp2_crypto_ossl.h>
#include <openssl/ssl.h>

#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char irock_hy2_last_error_stage[32];
static int irock_hy2_last_error_code;

void irock_hy2_set_last_error_for_testing(const char *stage, int code) {
  if (!stage || !stage[0]) {
    irock_hy2_last_error_stage[0] = '\0';
    irock_hy2_last_error_code = 0;
    return;
  }
  strncpy(irock_hy2_last_error_stage, stage, sizeof(irock_hy2_last_error_stage) - 1);
  irock_hy2_last_error_stage[sizeof(irock_hy2_last_error_stage) - 1] = '\0';
  irock_hy2_last_error_code = code;
}

int irock_hy2_copy_last_error_for_testing(char *stage_buffer, int stage_buffer_length, int *code) {
  if (!stage_buffer || stage_buffer_length <= 0 || !code || !irock_hy2_last_error_stage[0]) {
    return 0;
  }
  size_t stage_length = strlen(irock_hy2_last_error_stage);
  if (stage_length >= (size_t)stage_buffer_length) {
    return 0;
  }
  memcpy(stage_buffer, irock_hy2_last_error_stage, stage_length + 1);
  *code = irock_hy2_last_error_code;
  return 1;
}

static char *irock_hy2_trimmed_copy(const char *value) {
  if (!value) {
    return 0;
  }

  const char *start = value;
  while (*start && isspace((unsigned char)*start)) {
    start++;
  }
  const char *end = start + strlen(start);
  while (end > start && isspace((unsigned char)*(end - 1))) {
    end--;
  }

  size_t length = (size_t)(end - start);
  char *copy = malloc(length + 1);
  if (!copy) {
    return 0;
  }
  memcpy(copy, start, length);
  copy[length] = '\0';
  return copy;
}

static int irock_hy2_copy_c_string(char *buffer, int buffer_length, const char *value) {
  size_t value_length = strlen(value);
  if (!buffer || buffer_length <= 0 || value_length >= (size_t)buffer_length) {
    return 0;
  }

  memcpy(buffer, value, value_length + 1);
  return 1;
}

static void irock_hy2_session_release_fields(struct irock_hy2_session *session) {
  if (!session) {
    return;
  }

  while (session->streams) {
    struct irock_hy2_stream *stream = session->streams;
    session->streams = stream->next;
    stream->next = 0;
    stream->session = 0;
    irock_hy2_stream_release(stream);
    free(stream);
  }

  if (session->udp_fd >= 0 && session->owns_udp_fd) {
    close(session->udp_fd);
  }
  if (session->http3_conn) {
    nghttp3_conn_del(session->http3_conn);
  }
  if (session->quic_conn) {
    ngtcp2_conn_del(session->quic_conn);
  }
  if (session->ssl) {
    SSL_set_app_data(session->ssl, 0);
    SSL_free(session->ssl);
  }
  if (session->ssl_ctx) {
    SSL_CTX_free(session->ssl_ctx);
  }
  if (session->crypto_ctx) {
    ngtcp2_crypto_ossl_ctx_del(session->crypto_ctx);
  }
  free(session->conn_ref);
  free(session->server_host);
  free(session->server_name);
  free(session->alpn);
  free(session->certificate_pin_sha256);
}

static irock_hy2_result irock_hy2_connect_quic_session_state(irock_hy2_session_ref created_session, irock_hy2_session_ref *session) {
  irock_hy2_set_last_error_for_testing(0, 0);
  irock_hy2_result result = irock_hy2_session_initialize_udp_for_testing(created_session);
  if (result != IROCK_HY2_OK) {
    irock_hy2_set_last_error_for_testing("udp_init", result);
  }
  if (result == IROCK_HY2_OK) {
    result = irock_hy2_session_initialize_tls_for_testing(created_session);
    if (result != IROCK_HY2_OK) {
      irock_hy2_set_last_error_for_testing("tls_init", result);
    }
  }
  if (result == IROCK_HY2_OK) {
    result = irock_hy2_session_initialize_quic_for_testing(created_session);
    if (result != IROCK_HY2_OK) {
      irock_hy2_set_last_error_for_testing("quic_init", result);
    }
  }
  if (result == IROCK_HY2_OK) {
    int bytes_written = 0;
    int packets_read = 0;
    int handshake_completed = 0;
    result = irock_hy2_session_run_quic_handshake_until_blocked_for_testing(created_session, 20, 100, &bytes_written, &packets_read, &handshake_completed);
    if (result != IROCK_HY2_OK) {
      irock_hy2_set_last_error_for_testing("quic_handshake", result);
    }
  }
  if (result != IROCK_HY2_OK) {
    if (result == IROCK_HY2_BLOCKED) {
      irock_hy2_set_last_error_for_testing("connect_blocked", result);
    }
    irock_hy2_session_free(created_session);
    return result == IROCK_HY2_BLOCKED ? IROCK_HY2_NETWORK_FAILED : result;
  }

  struct irock_hy2_session *hy2_session = created_session;
  hy2_session->authenticated = 1;
  *session = created_session;
  return IROCK_HY2_OK;
}

static irock_hy2_result irock_hy2_connect_session(irock_hy2_session_ref created_session, const char *authentication, irock_hy2_session_ref *session) {
  irock_hy2_set_last_error_for_testing(0, 0);
  irock_hy2_result result = irock_hy2_session_initialize_udp_for_testing(created_session);
  if (result != IROCK_HY2_OK) {
    irock_hy2_set_last_error_for_testing("udp_init", result);
  }
  if (result == IROCK_HY2_OK) {
    result = irock_hy2_session_initialize_tls_for_testing(created_session);
    if (result != IROCK_HY2_OK) {
      irock_hy2_set_last_error_for_testing("tls_init", result);
    }
  }
  if (result == IROCK_HY2_OK) {
    result = irock_hy2_session_initialize_quic_for_testing(created_session);
    if (result != IROCK_HY2_OK) {
      irock_hy2_set_last_error_for_testing("quic_init", result);
    }
  }
  if (result == IROCK_HY2_OK) {
    result = irock_hy2_session_initialize_http3_for_testing(created_session);
    if (result != IROCK_HY2_OK) {
      irock_hy2_set_last_error_for_testing("http3_init", result);
    }
  }
  if (result == IROCK_HY2_OK) {
    result = irock_hy2_session_submit_http3_auth_for_testing(created_session, authentication, 250);
    if (result != IROCK_HY2_OK) {
      irock_hy2_set_last_error_for_testing("auth_submit", result);
    }
  }
  if (result == IROCK_HY2_OK) {
    int bytes_written = 0;
    int packets_read = 0;
    int handshake_completed = 0;
    result = irock_hy2_session_run_quic_handshake_until_blocked_for_testing(created_session, 20, 100, &bytes_written, &packets_read, &handshake_completed);
    if (result != IROCK_HY2_OK) {
      irock_hy2_set_last_error_for_testing("quic_handshake", result);
    }
  }
  if (result == IROCK_HY2_OK) {
    int bytes_written = 0;
    int packets_read = 0;
    int auth_status = 0;
    result = irock_hy2_session_run_http3_auth_for_testing(created_session, 64, 100, &bytes_written, &packets_read, &auth_status);
    if (result != IROCK_HY2_OK) {
      char stage[32];
      int code = 0;
      if (!irock_hy2_copy_last_error_for_testing(stage, (int)sizeof(stage), &code)) {
        irock_hy2_set_last_error_for_testing("http3_auth", result);
      }
    }
  }
  if (result != IROCK_HY2_OK) {
    if (result == IROCK_HY2_BLOCKED) {
      irock_hy2_set_last_error_for_testing("connect_blocked", result);
    }
    irock_hy2_session_free(created_session);
    return result == IROCK_HY2_BLOCKED ? IROCK_HY2_NETWORK_FAILED : result;
  }

  *session = created_session;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_connect(const irock_hy2_client_config *config, const char *authentication, irock_hy2_session_ref *session) {
  (void)ngtcp2_version(0);
  (void)nghttp3_version(0);
  (void)ngtcp2_crypto_ossl_init();

  if (session) {
    *session = 0;
  }

  if (!config || !config->server_host || !config->server_name || !config->alpn || !authentication || !authentication[0] || !session) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  irock_hy2_session_ref created_session = 0;
  irock_hy2_result result = irock_hy2_session_create_configured_for_testing(config, authentication, 0, &created_session);
  if (result != IROCK_HY2_OK) {
    return result;
  }
  return irock_hy2_connect_session(created_session, authentication, session);
}

irock_hy2_result irock_hy2_connect_with_connected_udp_socket(const irock_hy2_client_config *config, const char *authentication, int udp_fd, int remote_port, irock_hy2_session_ref *session) {
  (void)ngtcp2_version(0);
  (void)nghttp3_version(0);
  (void)ngtcp2_crypto_ossl_init();

  if (session) {
    *session = 0;
  }

  if (!config || !config->server_host || !config->server_name || !config->alpn || !authentication || !authentication[0] || !session) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  irock_hy2_session_ref created_session = 0;
  irock_hy2_result result = irock_hy2_session_create_configured_for_testing(config, authentication, 0, &created_session);
  if (result == IROCK_HY2_OK) {
    result = irock_hy2_session_use_connected_udp_socket_for_testing(created_session, udp_fd, remote_port);
  }
  if (result != IROCK_HY2_OK) {
    irock_hy2_session_free(created_session);
    return result;
  }
  return irock_hy2_connect_session(created_session, authentication, session);
}

irock_hy2_result irock_hy2_connect_quic_session(const irock_hy2_client_config *config, irock_hy2_session_ref *session) {
  (void)ngtcp2_version(0);
  (void)nghttp3_version(0);
  (void)ngtcp2_crypto_ossl_init();

  if (session) {
    *session = 0;
  }

  if (!config || !config->server_host || !config->server_name || !config->alpn || !session) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  irock_hy2_session_ref created_session = 0;
  irock_hy2_result result = irock_hy2_session_create_configured_for_testing(config, "quic-session", 0, &created_session);
  if (result != IROCK_HY2_OK) {
    return result;
  }
  return irock_hy2_connect_quic_session_state(created_session, session);
}

irock_hy2_result irock_hy2_session_create_for_testing(int authenticated, irock_hy2_session_ref *session) {
  if (session) {
    *session = 0;
  }
  if (!session) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *created_session = malloc(sizeof(struct irock_hy2_session));
  if (!created_session) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  created_session->authenticated = authenticated ? 1 : 0;
  created_session->server_host = 0;
  created_session->server_port = 0;
  created_session->server_name = 0;
  created_session->alpn = 0;
  created_session->allow_insecure = 0;
  created_session->certificate_pin_sha256 = 0;
  created_session->ssl_ctx = 0;
  created_session->ssl = 0;
  created_session->crypto_ctx = 0;
  created_session->client_session_configured = 0;
  created_session->udp_fd = -1;
  created_session->owns_udp_fd = 0;
  created_session->remote_port = 0;
  created_session->quic_conn = 0;
  created_session->conn_ref = 0;
  created_session->http3_conn = 0;
  created_session->auth_stream_id = -1;
  created_session->auth_status = 0;
  created_session->http3_open_stream_count = 0;
  created_session->has_quic_path = 0;
  created_session->last_quic_bytes_written = 0;
  created_session->streams = 0;
  *session = created_session;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_create_configured_for_testing(const irock_hy2_client_config *config, const char *authentication, int authenticated, irock_hy2_session_ref *session) {
  if (session) {
    *session = 0;
  }
  if (!config || !config->server_host || !config->server_name || !config->alpn || !authentication || !authentication[0] || !session) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *created_session = malloc(sizeof(struct irock_hy2_session));
  if (!created_session) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  created_session->authenticated = authenticated ? 1 : 0;
  created_session->server_host = irock_hy2_trimmed_copy(config->server_host);
  created_session->server_port = config->server_port;
  created_session->server_name = irock_hy2_trimmed_copy(config->server_name);
  created_session->alpn = irock_hy2_trimmed_copy(config->alpn);
  created_session->allow_insecure = config->allow_insecure ? 1 : 0;
  created_session->certificate_pin_sha256 = irock_hy2_trimmed_copy(config->certificate_pin_sha256 ? config->certificate_pin_sha256 : "");
  created_session->ssl_ctx = 0;
  created_session->ssl = 0;
  created_session->crypto_ctx = 0;
  created_session->client_session_configured = 0;
  created_session->udp_fd = -1;
  created_session->owns_udp_fd = 0;
  created_session->remote_port = 0;
  created_session->quic_conn = 0;
  created_session->conn_ref = 0;
  created_session->http3_conn = 0;
  created_session->auth_stream_id = -1;
  created_session->auth_status = 0;
  created_session->http3_open_stream_count = 0;
  created_session->has_quic_path = 0;
  created_session->last_quic_bytes_written = 0;
  created_session->streams = 0;
  if (!created_session->server_host || !created_session->server_host[0] || !created_session->server_name || !created_session->server_name[0] || !created_session->alpn || !created_session->alpn[0]) {
    irock_hy2_session_release_fields(created_session);
    free(created_session);
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  *session = created_session;
  return IROCK_HY2_OK;
}

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
) {
  if (!session || !server_port || !allow_insecure || !authentication_stored) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (!hy2_session->server_host || !hy2_session->server_name || !hy2_session->alpn) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }
  if (!irock_hy2_copy_c_string(host_buffer, host_buffer_length, hy2_session->server_host) || !irock_hy2_copy_c_string(server_name_buffer, server_name_buffer_length, hy2_session->server_name) || !irock_hy2_copy_c_string(alpn_buffer, alpn_buffer_length, hy2_session->alpn) || !irock_hy2_copy_c_string(certificate_pin_buffer, certificate_pin_buffer_length, hy2_session->certificate_pin_sha256 ? hy2_session->certificate_pin_sha256 : "")) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  *server_port = hy2_session->server_port;
  *allow_insecure = hy2_session->allow_insecure;
  *authentication_stored = 0;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_apply_auth_status(irock_hy2_session_ref session, int status_code) {
  if (!session) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  irock_hy2_result result = irock_hy2_validate_auth_status(status_code);
  if (result == IROCK_HY2_OK) {
    struct irock_hy2_session *hy2_session = session;
    hy2_session->authenticated = 1;
  }
  return result;
}

void irock_hy2_session_free(irock_hy2_session_ref session) {
  irock_hy2_session_release_fields(session);
  free(session);
}
