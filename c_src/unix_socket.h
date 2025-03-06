#ifndef UNIX_SOCKET_H
#define UNIX_SOCKET_H

#include <string>
#include <stdexcept>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

class UnixSocket {
public:
    UnixSocket(const std::string &socket_path);
    ~UnixSocket();

    void Send(const std::string &data);
    std::string Receive();

private:
    int socket_fd_;
    std::string socket_path_;
};

#endif