all:
	gitbook build

pdf:
	gitbook pdf

serve:
	gitbook serve > .gitbook-serve.log 2>&1 &

view:
	chromium-browser http://localhost:4000

read-pdf:
	chromium-browser book.pdf

read: read-html

read-html:
	chromium-browser _book/index.html

clean:
	@rm -rf _book

distclean: clean
	@rm book*.pdf
