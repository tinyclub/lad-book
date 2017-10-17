all:
	gitbook build

pdf:
	gitbook pdf

read-pdf:
	chromium-browser book.pdf

read: read-html

read-html:
	chromium-browser _book/index.html

clean:
	@rm -rf _book

distclean: clean
	@rm book.pdf
