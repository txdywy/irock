#include "irock_native_hysteria2_runtime.h"
#include "irock_hy2_internal.h"

#include <ngtcp2/ngtcp2_crypto_ossl.h>
#include <openssl/ssl.h>
#include <string.h>

static irock_hy2_result irock_hy2_set_alpn(SSL *ssl, const char *alpn) {
  if (!ssl || !alpn || !alpn[0]) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  size_t alpn_length = strlen(alpn);
  if (alpn_length > 255) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  unsigned char wire_alpn[256];
  wire_alpn[0] = (unsigned char)alpn_length;
  memcpy(wire_alpn + 1, alpn, alpn_length);
  return SSL_set_alpn_protos(ssl, wire_alpn, (unsigned int)(alpn_length + 1)) == 0 ? IROCK_HY2_OK : IROCK_HY2_INVALID_CONFIGURATION;
}

irock_hy2_result irock_hy2_session_initialize_tls_for_testing(irock_hy2_session_ref session) {
  if (!session) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (!hy2_session->server_name || !hy2_session->server_name[0] || !hy2_session->alpn || !hy2_session->alpn[0]) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }
  if (ngtcp2_crypto_ossl_init() != 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  hy2_session->ssl_ctx = SSL_CTX_new(TLS_client_method());
  if (!hy2_session->ssl_ctx) {
    return IROCK_HY2_NETWORK_FAILED;
  }
  if (!hy2_session->allow_insecure) {
    SSL_CTX_set_default_verify_paths(hy2_session->ssl_ctx);
    SSL_CTX_set_verify(hy2_session->ssl_ctx, SSL_VERIFY_PEER, 0);
  } else {
    SSL_CTX_set_verify(hy2_session->ssl_ctx, SSL_VERIFY_NONE, 0);
  }

  hy2_session->ssl = SSL_new(hy2_session->ssl_ctx);
  if (!hy2_session->ssl) {
    return IROCK_HY2_NETWORK_FAILED;
  }
  SSL_set_connect_state(hy2_session->ssl);
  if (SSL_set_tlsext_host_name(hy2_session->ssl, hy2_session->server_name) != 1) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }
  irock_hy2_result alpn_result = irock_hy2_set_alpn(hy2_session->ssl, hy2_session->alpn);
  if (alpn_result != IROCK_HY2_OK) {
    return alpn_result;
  }
  if (ngtcp2_crypto_ossl_configure_client_session(hy2_session->ssl) != 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }
  hy2_session->client_session_configured = 1;

  if (ngtcp2_crypto_ossl_ctx_new(&hy2_session->crypto_ctx, hy2_session->ssl) != 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_copy_tls_state_for_testing(
  irock_hy2_session_ref session,
  int *has_ssl_context,
  int *has_ssl,
  int *has_crypto_context,
  int *client_session_configured
) {
  if (!session || !has_ssl_context || !has_ssl || !has_crypto_context || !client_session_configured) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  *has_ssl_context = hy2_session->ssl_ctx ? 1 : 0;
  *has_ssl = hy2_session->ssl ? 1 : 0;
  *has_crypto_context = hy2_session->crypto_ctx ? 1 : 0;
  *client_session_configured = hy2_session->client_session_configured;
  return IROCK_HY2_OK;
}
