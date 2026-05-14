#include "irock_native_hysteria2_runtime.h"
#include "irock_hy2_internal.h"

#include <ngtcp2/ngtcp2_crypto_ossl.h>
#include <openssl/evp.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <string.h>

irock_hy2_result irock_hy2_validate_certificate_pin_for_testing(const uint8_t *certificate_bytes, int certificate_byte_count, const char *certificate_pin_sha256) {
  if (!certificate_pin_sha256 || !certificate_pin_sha256[0]) {
    return IROCK_HY2_OK;
  }
  if (!certificate_bytes || certificate_byte_count <= 0) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  unsigned char digest[EVP_MAX_MD_SIZE];
  unsigned int digest_length = 0;
  if (EVP_Digest(certificate_bytes, (size_t)certificate_byte_count, digest, &digest_length, EVP_sha256(), 0) != 1) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  unsigned char encoded[128];
  int encoded_length = EVP_EncodeBlock(encoded, digest, digest_length);
  if (encoded_length <= 0 || encoded_length >= (int)sizeof(encoded)) {
    return IROCK_HY2_NETWORK_FAILED;
  }
  encoded[encoded_length] = '\0';
  return strcmp((const char *)encoded, certificate_pin_sha256) == 0 ? IROCK_HY2_OK : IROCK_HY2_AUTH_FAILED;
}

irock_hy2_result irock_hy2_session_validate_peer_certificate_pin_for_testing(irock_hy2_session_ref session) {
  if (!session) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (!hy2_session->certificate_pin_sha256 || !hy2_session->certificate_pin_sha256[0]) {
    return IROCK_HY2_OK;
  }
  if (!hy2_session->ssl) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  X509 *certificate = SSL_get1_peer_certificate(hy2_session->ssl);
  if (!certificate) {
    return IROCK_HY2_AUTH_FAILED;
  }
  unsigned char *der = 0;
  int der_length = i2d_X509(certificate, &der);
  X509_free(certificate);
  if (der_length <= 0 || !der) {
    OPENSSL_free(der);
    return IROCK_HY2_NETWORK_FAILED;
  }
  irock_hy2_result result = irock_hy2_validate_certificate_pin_for_testing(der, der_length, hy2_session->certificate_pin_sha256);
  OPENSSL_free(der);
  return result;
}

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
