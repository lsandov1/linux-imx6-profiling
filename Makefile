MD_SOURCE = markdown/slides.md

.PHONY: all

all: slidy/index.html

slidy/index.html: $(MD_SOURCE) slidy.template Makefile
	pandoc -t slidy --slide-level 2 --template slidy.template -o $@ $(MD_SOURCE)

clean:
	-rm -f slidy/index.html
