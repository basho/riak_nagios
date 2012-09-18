REBAR_BIN := ./rebar
REBAR_CONFIG := ./rebar.config
REBAR := $(REBAR_BIN) -C $(REBAR_CONFIG)
ifdef suites
	SUITE_OPTION := suites=$(suites)
endif
EUNIT_OPTIONS := $(SUITE_OPTION)

.PHONY: deps test

all: deps compile

deps:
	$(REBAR) get-deps

compile: deps
	$(REBAR) compile

clean:
	$(REBAR) clean

distclean: clean
	$(REBAR) delete-deps

test: compile
	$(REBAR) skip_deps=true $(EUNIT_OPTIONS) eunit

console: compile
	erl -pa ebin deps/*/ebin

escript: compile
	$(REBAR) skip_deps=true escriptize
