.ONESHELL:
.SILENT:
.EXPORT_ALL_VARIABLES:

MAKEFLAGS += --no-builtin-rules --no-builtin-variables

###############################################################################
# Settings
###############################################################################

gpg_key := 1A4A6FC0BB90A4B5F2A11031E577D405DD6ABEA5

txt := $(shell ls -1 | grep -vE '.asc|makefile|README.md' | tr '\n' ' ')
asc := $(addsuffix .asc,$(txt))

###############################################################################
# Targets
###############################################################################

.PHONY: help decrypt encrypt clean

help:
	$(call header,Settings)
	$(call var,GPG_KEY,$(gpg_key))
	$(call header,Help)
	$(call help,make decrypt,Decrypt all secrets)
	$(call help,make encrypt,Encrypt all secrets)
	$(call help,make clean,Remove unencrypted secrets)

decrypt:
	$(call header,Decrypting secrets)
	$(foreach file,$(wildcard *.asc),gpg $(file) && touch $(file) && chmod 600 $(file:%.asc=%);)

encrypt:
	$(call header,Encrypting secrets)
	$(foreach file,$(txt),gpg -aer $(gpg_key) $(file);)

$(asc): $(txt)
	$(call header,Encrypting $@)
	gpg -aer $(gpg_key) $(@:%.asc=%)

clean:
	$(call header,Removing unencrypted secrets)
	$(foreach file,$(txt),shred -uf $(file);)

###############################################################################
# Colors and Headers
###############################################################################

black := \033[30m
red := \033[31m
green := \033[32m
yellow := \033[33m
blue := \033[34m
magenta := \033[35m
cyan := \033[36m
white := \033[37m
reset := \033[0m

define header
echo "$(blue)==> $(1) <==$(reset)"
endef

define help
echo "$(green)$(1)$(reset) - $(white)$(2)$(reset)"
endef

define var
echo "$(magenta)$(1)$(reset): $(yellow)$(2)$(reset)"
endef
