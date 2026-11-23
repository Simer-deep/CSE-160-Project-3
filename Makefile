COMPONENT=NodeC


INCLUDE=-IdataStructures
INCLUDE+=-IdataStructures/interfaces/ -IdataStructures/modules
INCLUDE+=-Ilib/interfaces -Ilib/modules

ifeq ($(EXTRA_CREDIT),1)
INCLUDE+=-I"extra credit/interfaces" -I"extra credit/modules"
CFLAGS += -DEXTRA_CREDIT_CONGESTION
endif

CFLAGS += -DTOSH_DATA_LENGTH=29
CFLAGS+=$(INCLUDE)

include $(TINYOS_ROOT_DIR)/Makefile.include

CommandMsg.py: CommandMsg.h
	nescc-mig python -python-classname=CommandMsg CommandMsg.h CommandMsg -o $@

packet.py: packet.h
	nescc-mig python -python-classname=pack packet.h pack -o packet.py
