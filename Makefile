REBAR := ./rebar

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
ifdef suite
	$(REBAR) skip_deps=true eunit suite=$(suite)
else
	$(REBAR) skip_deps=true eunit
endif

console: compile
	erl -pa ebin deps/*/ebin

escript: compile
	$(REBAR) skip_deps=true escriptize
