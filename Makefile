PROJECT = carrot
PROJECT_DESCRIPTION = Rabbit MQ Feed Producer and Consumer
PROJECT_VERSION = 1.0.0

DEPS = amqp_client uuid
TEST_DEPS = gproc

BUILD_DEPS = elvis_mk

dep_elvis_mk = git https://github.com/inaka/elvis.mk.git d22ee4aeefad3886bdedb87bec7645626b19e198

DEP_PLUGINS = elvis_mk

include erlang.mk

build:	all elvis dialyze tests
