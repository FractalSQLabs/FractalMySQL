# mysql-fractalsql Makefile — local (non-Docker) development build.
#
# For shipping artifacts, use:
#   ./build.sh        (Docker, static LuaJIT, hardened posture,
#                      outputs dist/${arch}/fractalsql.so)
#
# This Makefile is for quick iteration against whatever
# libmysqlclient-dev and libluajit-5.1-dev happen to be on your path.
# It produces a dynamically-linked fractalsql.so; the shipped artifact
# is always the Docker one.
#
# Build:   make
# Install: sudo make install
# Load:    mysql -u root -p < sql/install_udf.sql

CC      = gcc

# LuaJIT headers live under /usr/include/luajit-2.1/ on Debian/Ubuntu;
# prefer pkg-config and fall back to the common system path.
LUAJIT_CFLAGS := $(shell pkg-config --cflags luajit 2>/dev/null)
LUAJIT_LIBS   := $(shell pkg-config --libs luajit 2>/dev/null)
ifeq ($(strip $(LUAJIT_CFLAGS)),)
  LUAJIT_CFLAGS := -I/usr/include/luajit-2.1
  LUAJIT_LIBS   := -lluajit-5.1
endif

CFLAGS  = -Wall -Wextra -O3 -fPIC $(shell mysql_config --cflags) \
          $(LUAJIT_CFLAGS) -Iinclude
LDFLAGS = -shared $(LUAJIT_LIBS) -lm

TARGET = fractalsql.so
SRCS   = src/fractalsql.c
OBJS   = $(SRCS:.c=.o)

# MySQL's plugin dir (mysql_config --plugindir). Fall back to a common
# location if mysql_config doesn't report one.
PLUGIN_DIR := $(shell mysql_config --plugindir 2>/dev/null)
ifeq ($(strip $(PLUGIN_DIR)),)
  PLUGIN_DIR := /usr/lib/mysql/plugin
endif

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

%.o: %.c include/sfs_core_bc.h
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)

install: $(TARGET)
	cp $(TARGET) $(PLUGIN_DIR)

.PHONY: all clean install
