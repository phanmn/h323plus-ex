#ifndef UNIXSOCKETCHANNEL_H
#define UNIXSOCKETCHANNEL_H

#include <ptlib.h>
#include <ptlib/channel.h>

class UnixSocketChannel : public PChannel {
public:
    UnixSocketChannel(const std::string &socketPath);
    ~UnixSocketChannel();

    bool IsOpen() const override;
    bool Write(const void *buf, PINDEX len) override;
    bool Read(void *buf, PINDEX len) override;
    PBoolean Close() override;

private:
    int sockFd;   // Raw Unix socket file descriptor
    bool connected;
};

#endif // UNIXSOCKETCHANNEL_H
