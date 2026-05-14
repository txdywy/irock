#ifndef IROCK_HY2_INTERNAL_H
#define IROCK_HY2_INTERNAL_H

#include "irock_native_hysteria2_runtime.h"

#include <stdint.h>

typedef struct ssl_ctx_st SSL_CTX;
typedef struct ssl_st SSL;
typedef struct ngtcp2_crypto_ossl_ctx ngtcp2_crypto_ossl_ctx;
typedef struct ngtcp2_crypto_conn_ref ngtcp2_crypto_conn_ref;
typedef struct ngtcp2_conn ngtcp2_conn;
typedef struct nghttp3_conn nghttp3_conn;

struct irock_hy2_session;

struct irock_hy2_stream {
  struct irock_hy2_session *session;
  int64_t stream_id;
  int request_bytes_written;
  uint8_t request_bytes[256];
  int request_bytes_sent;
  uint8_t *read_buffer;
  int read_buffer_length;
  int read_buffer_capacity;
  uint8_t *write_buffer;
  int write_buffer_length;
  int write_buffer_sent;
  int read_closed;
  struct irock_hy2_stream *next;
};

struct irock_hy2_stream *irock_hy2_session_find_stream(struct irock_hy2_session *session, int64_t stream_id);
irock_hy2_result irock_hy2_session_register_stream(struct irock_hy2_session *session, struct irock_hy2_stream *stream);
void irock_hy2_session_unregister_stream(struct irock_hy2_session *session, struct irock_hy2_stream *stream);
void irock_hy2_stream_release(struct irock_hy2_stream *stream);

struct irock_hy2_session {
  int authenticated;
  char *server_host;
  int server_port;
  char *server_name;
  char *alpn;
  int allow_insecure;
  char *certificate_pin_sha256;
  SSL_CTX *ssl_ctx;
  SSL *ssl;
  ngtcp2_crypto_ossl_ctx *crypto_ctx;
  int client_session_configured;
  int udp_fd;
  int owns_udp_fd;
  int remote_port;
  ngtcp2_conn *quic_conn;
  ngtcp2_crypto_conn_ref *conn_ref;
  nghttp3_conn *http3_conn;
  int64_t auth_stream_id;
  int auth_status;
  int64_t http3_open_stream_ids[16];
  int http3_open_stream_count;
  int has_quic_path;
  int last_quic_bytes_written;
  struct irock_hy2_stream *streams;
};

#endif
