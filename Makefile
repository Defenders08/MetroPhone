# Корневой переходник: настоящий theos-проект лежит в tweak/.
# Привычные команды работают в корне как раньше — просто пробрасываются туда:
#   make            — собрать
#   make package    — собрать deb (упадёт в builds/)
#   make clean      — почистить
# Переменные пробрасываются сами: make package FINALPACKAGE=0 и т.п.
.DEFAULT_GOAL := all
all:
	@$(MAKE) -C tweak
%::
	@$(MAKE) -C tweak $@
.PHONY: all
