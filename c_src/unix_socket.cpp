#include "unix_socket.h"
#include <errno.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>


UnixSocket::UnixSocket(const std::string &socket_path) : socket_path_(socket_path) {
  // Create a UNIX domain socket
  socket_fd_ = socket(AF_UNIX, SOCK_STREAM, 0);
  if (socket_fd_ == -1) {
    throw std::runtime_error("Failed to create socket: " +
                             std::string(strerror(errno)));
  }

  // Set up the socket address
  sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, socket_path_.c_str(), sizeof(addr.sun_path) - 1);

  // Bind the socket to the address
  if (bind(socket_fd_, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
    close(socket_fd_);
    throw std::runtime_error("Failed to bind socket: " +
                             std::string(strerror(errno)));
  }
}

UnixSocket::~UnixSocket() {
  if (socket_fd_ != -1) {
    close(socket_fd_);
  }
}

void UnixSocket::Send(const std::string &data) {
  if (send(socket_fd_, data.c_str(), data.length(), 0) == -1) {
    throw std::runtime_error("Failed to send data: " +
                             std::string(strerror(errno)));
  }
}

std::string UnixSocket::Receive() {
  char buffer[1024];
  ssize_t bytes_received = recv(socket_fd_, buffer, sizeof(buffer) - 1, 0);
  if (bytes_received == -1) {
    throw std::runtime_error("Failed to receive data: " +
                             std::string(strerror(errno)));
  }
  buffer[bytes_received] = '\0';
  return std::string(buffer);
}
