all: build

PUML:=$(wildcard *.puml)
SVGS:=$(patsubst %.puml,%.svg,$(PUML))

%.svg: %.puml
	plantuml -tsvg $?

build: $(SVGS)

upload: $(SVGS)
	aws s3 cp . s3://cnx.vmware/cicd/yakity/svg/ \
	  --recursive --exclude "*" \
	  $(foreach f,$(SVGS),--include "$(f)") \
	  --grants read=uri=http://acs.amazonaws.com/groups/global/AllUsers

.PHONY: upload
