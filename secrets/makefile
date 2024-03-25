.ONESHELL:
.SILENT:
.EXPORT_ALL_VARIABLES:

gpg_key := 1A4A6FC0BB90A4B5F2A11031E577D405DD6ABEA5

txt := $(shell ls -1 | grep -vE '.asc|makefile|README.md' | tr '\n' ' ')
asc := $(addsuffix .asc,$(txt))

help:
	echo "Help:"
	echo "  make decrypt        # Decrypt all secrets"
	echo "  make encrypt        # Encrypt all secrets"
	echo "  make <secret_name>  # Encrypt a secret"
	echo "  make clean          # Remove unencrypted secrets"

decrypt:
	$(info ==> Decrypting secrets <==)
	for file in *.asc; do
		gpg $${file}
	done
	for file in *.asc; do
		touch $${file}
	done

encrypt:
	$(info ==> Encrypting secrets <==)
	for file in $(txt); do
		gpg -a -e -r $(gpg_key) $${file}
	done

$(asc): $(txt)
	$(info ==> Encrypting $@ <==)
	gpg -a -e -r $(gpg_key) $(@:%.asc=%)

clean:
	$(info ==> Removing unencrypted secrets <==)
	for file in $(txt); do
		rm $${file}
	done
