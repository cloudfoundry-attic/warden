default: all

# Proxy any target to the Makefiles in the per-tool directories
%:
	cd clone && $(MAKE) $@
	cd oom && $(MAKE) $@
	cd repquota && $(MAKE) $@
	cd iomux && $(MAKE) $@

.PHONY: default
