#include "unix_socket.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <iostream>
#include <cstring>

UnixSocketChannel::UnixSocketChannel(const std::string &socketPath) : sockFd(-1), connected(false) {
    std::cout << "Start connect to UNIX socket!" << std::endl;

    sockFd = ::socket(AF_UNIX, SOCK_STREAM, 0);  // Use `::socket` to avoid conflicts
    if (sockFd < 0) {
        perror("Socket creation failed");
        return;
    }

    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socketPath.c_str(), sizeof(addr.sun_path) - 1);

    if (::connect(sockFd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {  // Use `::connect`
        perror("Socket connection failed");
        ::close(sockFd);
        sockFd = -1;
        return;
    }

    connected = true;
}

UnixSocketChannel::~UnixSocketChannel() {
    if (sockFd >= 0) {
        Close();
    }
}

bool UnixSocketChannel::IsOpen() const {
    return connected && sockFd >= 0;
}

bool UnixSocketChannel::Write(const void *buf, PINDEX len) {
    if (!IsOpen()) return false;
    const char *data = static_cast<const char*>(buf);
    ssize_t totalWritten = 0;
    while (totalWritten < (ssize_t)len) {
        ssize_t written = ::write(sockFd, data + totalWritten, len - totalWritten);
        if (written <= 0) {
            return false;
        }
        totalWritten += written;
    }
    return true;
}

bool UnixSocketChannel::Read(void *buf, PINDEX len) {
    if (!IsOpen()) return false;
    ssize_t bytesRead = ::read(sockFd, buf, len);
    if (bytesRead <= 0) {  // Handle EOF or error
        return false;
    }
    return true;
}

PBoolean UnixSocketChannel::Close() {
    if (sockFd >= 0) {
        ::close(sockFd);  // Use `::close`
        sockFd = -1;
        connected = false;
        return true;
    }
    return false;
}
