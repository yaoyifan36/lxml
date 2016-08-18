PYTHON?=python
PYTHON3?=python3
TESTFLAGS=-p -v
TESTOPTS=
SETUPFLAGS=
LXMLVERSION=`cat version.txt`

PYTHON_WITH_CYTHON=$(shell $(PYTHON)  -c 'import Cython.Build.Dependencies' >/dev/null 2>/dev/null && echo " --with-cython" || true)
PY3_WITH_CYTHON=$(shell $(PYTHON3) -c 'import Cython.Build.Dependencies' >/dev/null 2>/dev/null && echo " --with-cython" || true)
CYTHON_WITH_COVERAGE=$(shell $(PYTHON) -c 'import Cython.Coverage; import sys; assert not hasattr(sys, "pypy_version_info")' >/dev/null 2>/dev/null && echo " --coverage" || true)
CYTHON3_WITH_COVERAGE=$(shell $(PYTHON3) -c 'import Cython.Coverage; import sys; assert not hasattr(sys, "pypy_version_info")' >/dev/null 2>/dev/null && echo " --coverage" || true)

MANYLINUX_IMAGE_X86_64=quay.io/pypa/manylinux1_x86_64

all: inplace

# Build in-place
inplace:
	$(PYTHON) setup.py $(SETUPFLAGS) build_ext -i $(PYTHON_WITH_CYTHON) --warnings --with-coverage

sdist:
	$(PYTHON) setup.py $(SETUPFLAGS) sdist $(PYTHON_WITH_CYTHON)

build:
	$(PYTHON) setup.py $(SETUPFLAGS) build $(PYTHON_WITH_CYTHON)

require-cython:
	@[ -n "$(PYTHON_WITH_CYTHON)" ] || { \
	    echo "NOTE: missing Cython - please use '$(PYTHON) -m pip install Cython' to install it"; false; }

wheel_manylinux: require-cython sdist
	time docker run --rm -t \
		-v $(shell pwd):/io \
		-e CFLAGS="$(CFLAGS)" \
		-e LDFLAGS="$(LDFLAGS)" \
		$(MANYLINUX_IMAGE_X86_64) \
		bash /io/tools/manylinux/build-wheels.sh /io/dist/lxml-$(LXMLVERSION).tar.gz

wheel:
	$(PYTHON) setup.py $(SETUPFLAGS) bdist_wheel $(PYTHON_WITH_CYTHON)

wheel_static:
	$(PYTHON) setup.py $(SETUPFLAGS) bdist_wheel $(PYTHON_WITH_CYTHON) --static-deps

test_build: build
	$(PYTHON) test.py $(TESTFLAGS) $(TESTOPTS)

test_inplace: inplace
	$(PYTHON) test.py $(TESTFLAGS) $(TESTOPTS) $(CYTHON_WITH_COVERAGE)

test_inplace3: inplace
	$(PYTHON3) setup.py $(SETUPFLAGS) build_ext -i $(PY3_WITH_CYTHON)
	$(PYTHON3) test.py $(TESTFLAGS) $(TESTOPTS) $(CYTHON3_WITH_COVERAGE)

valgrind_test_inplace: inplace
	valgrind --tool=memcheck --leak-check=full --num-callers=30 --suppressions=valgrind-python.supp \
		$(PYTHON) test.py

gdb_test_inplace: inplace
	@echo -e "file $(PYTHON)\nrun test.py" > .gdb.command
	gdb -x .gdb.command -d src -d src/lxml

bench_inplace: inplace
	$(PYTHON) benchmark/bench_etree.py -i
	$(PYTHON) benchmark/bench_xpath.py -i
	$(PYTHON) benchmark/bench_xslt.py -i
	$(PYTHON) benchmark/bench_objectify.py -i

ftest_build: build
	$(PYTHON) test.py -f $(TESTFLAGS) $(TESTOPTS)

ftest_inplace: inplace
	$(PYTHON) test.py -f $(TESTFLAGS) $(TESTOPTS)

apihtml: inplace
	rm -fr doc/html/api
	@[ -x "`which epydoc`" ] \
		&& (cd src && echo "Generating API docs ..." && \
			PYTHONPATH=. epydoc -v --docformat "restructuredtext en" \
			-o ../doc/html/api --exclude='[.]html[.]tests|[.]_' \
			--exclude-introspect='[.]usedoctest' \
			--name "lxml API" --url / lxml/) \
		|| (echo "not generating epydoc API documentation")

website: inplace
	PYTHONPATH=src:$(PYTHONPATH) $(PYTHON) doc/mkhtml.py doc/html . ${LXMLVERSION}

html: inplace website apihtml s5

s5:
	$(MAKE) -C doc/s5 slides

apipdf: inplace
	rm -fr doc/pdf
	mkdir -p doc/pdf
	@[ -x "`which epydoc`" ] \
		&& (cd src && echo "Generating API docs ..." && \
			PYTHONPATH=. epydoc -v --latex --docformat "restructuredtext en" \
			-o ../doc/pdf --exclude='([.]html)?[.]tests|[.]_' \
			--exclude-introspect='html[.]clean|[.]usedoctest' \
			--name "lxml API" --url / lxml/) \
		|| (echo "not generating epydoc API documentation")

pdf: apipdf
	$(PYTHON) doc/mklatex.py doc/pdf . ${LXMLVERSION}
	(cd doc/pdf && pdflatex lxmldoc.tex \
		    && pdflatex lxmldoc.tex \
		    && pdflatex lxmldoc.tex)
	@cp doc/pdf/lxmldoc.pdf doc/pdf/lxmldoc-${LXMLVERSION}.pdf
	@echo "PDF available as doc/pdf/lxmldoc-${LXMLVERSION}.pdf"

# Two pdflatex runs are needed to build the correct Table of contents.

test: test_inplace

test3: test_inplace3

valtest: valgrind_test_inplace

gdbtest: gdb_test_inplace

bench: bench_inplace

ftest: ftest_inplace

clean:
	find . \( -name '*.o' -o -name '*.so' -o -name '*.py[cod]' -o -name '*.dll' \) -exec rm -f {} \;
	rm -rf build

docclean:
	$(MAKE) -C doc/s5 clean
	rm -f doc/html/*.html
	rm -fr doc/html/api
	rm -fr doc/pdf

realclean: clean docclean
	find src -name '*.c' -exec rm -f {} \;
	rm -f TAGS
	$(PYTHON) setup.py clean -a --without-cython
