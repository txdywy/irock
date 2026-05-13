#include "irock_native_hysteria2_runtime.h"
#include "irock_hy2_internal.h"

#include <fcntl.h>
#include <netdb.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

irock_hy2_result irock_hy2_session_initialize_udp_for_testing(irock_hy2_session_ref session) {
  if (!session) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  if (hy2_session->udp_fd >= 0) {
    return IROCK_HY2_OK;
  }
  if (!hy2_session->server_host || hy2_session->server_port <= 0) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  char port_text[16];
  snprintf(port_text, sizeof(port_text), "%d", hy2_session->server_port);
  struct addrinfo hints;
  memset(&hints, 0, sizeof(hints));
  hints.ai_socktype = SOCK_DGRAM;
  hints.ai_family = AF_UNSPEC;
  struct addrinfo *result = 0;
  if (getaddrinfo(hy2_session->server_host, port_text, &hints, &result) != 0 || !result) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  int fd = -1;
  for (struct addrinfo *candidate = result; candidate; candidate = candidate->ai_next) {
    fd = socket(candidate->ai_family, candidate->ai_socktype, candidate->ai_protocol);
    if (fd < 0) {
      continue;
    }
    if (connect(fd, candidate->ai_addr, candidate->ai_addrlen) == 0) {
      break;
    }
    close(fd);
    fd = -1;
  }
  freeaddrinfo(result);
  if (fd < 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }

  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) {
    close(fd);
    return IROCK_HY2_NETWORK_FAILED;
  }

  if (hy2_session->udp_fd >= 0 && hy2_session->owns_udp_fd) {
    close(hy2_session->udp_fd);
  }
  hy2_session->udp_fd = fd;
  hy2_session->owns_udp_fd = 1;
  hy2_session->remote_port = hy2_session->server_port;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_use_connected_udp_socket_for_testing(irock_hy2_session_ref session, int udp_fd, int remote_port) {
  if (!session || udp_fd < 0 || remote_port <= 0 || remote_port > 65535) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  int flags = fcntl(udp_fd, F_GETFL, 0);
  if (flags < 0 || fcntl(udp_fd, F_SETFL, flags | O_NONBLOCK) != 0) {
    return IROCK_HY2_NETWORK_FAILED;
  }
  if (hy2_session->udp_fd >= 0 && hy2_session->owns_udp_fd) {
    close(hy2_session->udp_fd);
  }
  hy2_session->udp_fd = udp_fd;
  hy2_session->owns_udp_fd = 1;
  hy2_session->remote_port = remote_port;
  return IROCK_HY2_OK;
}

irock_hy2_result irock_hy2_session_copy_udp_state_for_testing(irock_hy2_session_ref session, int *has_socket, int *remote_port) {
  if (!session || !has_socket || !remote_port) {
    return IROCK_HY2_INVALID_CONFIGURATION;
  }

  struct irock_hy2_session *hy2_session = session;
  *has_socket = hy2_session->udp_fd >= 0 ? 1 : 0;
  *remote_port = hy2_session->remote_port;
  return IROCK_HY2_OK;
}
