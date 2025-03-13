# Welcome to H323Plus-ex instruction

Hi! If you are reading this, you will have a bad day when touching in **h323** source code, starting from now. However, some people on this planet is still using **h323** devices, so, let get started!!!

# Installation

Clone this repo to your device
```
git clone https://github.com/phanmn/h323plus-ex
```
Remember to install **Elixir** and **Erlang** first, take a look on: [asdf-elixir](https://github.com/asdf-vm/asdf-elixir)
Update and install dependencies needed
```
sudo apt-get update
sudo apt-get update
```
h323plus-ex requires ptlib and h323plus to be compiled. For Linux user, some how it requires configure as shared library, therefor, Mac user don't have to added the --enable-shared option when configured
```
cd ~
git clone https://github.com/willamowius/ptlib.git
cd ptlib
export PTLIBDIR=~/ptlib
./configure --enable-shared
make

cd ~
git clone https://github.com/willamowius/h323plus.git
cd h323plus
export OPENH323DIR=~/h323plus
./configure --enable-shared
make

cd ~
git clone https://github.com/phanmn/h323plus-ex
cd h323plus-ex
make clean && make && mix deps.get && mix clean && mix compile
```
That's all for the install steps!!
> ***Note:*** Sometime your environment could missing some dependencies, just install it by **sudo apt install [name]**.

The Makefile is modified to compile elixir each time using make, you could change it if you want.

## How to use?
