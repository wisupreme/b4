# directory paths, relative to this directory:
XPL       = lib/xpl/code
LNPAS     = lib/linenoise
GEN	  = gen
PPU	  = $(GEN)
EXE	  = $(GEN)
RETROPATH = lib/retro
NGAROTEST = $(RETROPATH)/test/ngaro/ngarotest.py

# ROOT should be path back to this directory from GEN
ROOT      = ../

# compiler paths
FPC       = fpc -gl -B -Sgic -Fu$(XPL) -Fu$(LNPAS) -Fi$(XPL) -FE$(GEN)
PYTHON    = python

#------------------------------------------------------

targets:
	@echo 'available targets:'
	@echo '--------------------------'
	@echo 'make build -> build ./gen/retro'
	@echo 'make retro -> build and run ./gen/retro'
	@echo 'make test  -> run all tests'
	@echo
	@echo for grammar engine, cd ./pre

retro : build
	cd $(GEN); ./retro -e

build : init  ng/*.pas
	@$(FPC) ng/retro.pas

init    :
	@mkdir -p $(GEN)
	@rm -f $(GEN)/library $(GEN)/retroImage
	@git submodule init
	@git submodule update
	@ln -s ../$(RETROPATH)/library $(GEN)/library
	@ln -n $(RETROPATH)/retroImage $(GEN)/retroImage

test: test.ngaro test.core test.files. test.clean

test.ngaro : init
	cd $(GEN); $(PYTHON) $(ROOT)$(NGAROTEST) -n ./retro

test.files : init
	cd $(GEN); ./retro --with $(ROOT)$(RETROPATH)/test/files.rx

test.core : init
	cd $(GEN); ./retro --with $(ROOT)$(RETROPATH)/test/core.rx

test.clean : init
	cd $(GEN); rm -f *.img

