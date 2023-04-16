#!/usr/bin/make -f
# apparmor.d - Full set of apparmor profiles
# Copyright (C) 2022 Alexandre Pujol <alexandre@pujol.io>
# SPDX-License-Identifier: GPL-2.0-only

DESTDIR ?= /
BUILD := .build
PKGNAME := apparmor.d
VERSION := 0.$(shell git rev-list --count HEAD)-1
P = $(notdir $(wildcard ${BUILD}/apparmor.d/*))

.PHONY: all build enforce full install local $(P) pkg dpkg rpm lint clean

all: build

build:
	@go build -o ${BUILD}/ ./cmd/aa-log

enforce: build
	@./${BUILD}/prebuild

full: build
	@./${BUILD}/prebuild --complain --full

ROOT = $(shell find "${BUILD}/root" -type f -printf "%P\n")
PROFILES = $(shell find "${BUILD}/apparmor.d" -type f -printf "%P\n")
install:
	@install -Dm755 ${BUILD}/aa-log ${DESTDIR}/usr/bin/aa-log
	@for file in ${ROOT}; do \
		install -Dm0644 "${BUILD}/root/$${file}" "${DESTDIR}/$${file}"; \
	done;
	@for file in ${PROFILES}; do \
		install -Dm0644 "${BUILD}/apparmor.d/$${file}" "${DESTDIR}/etc/apparmor.d/$${file}"; \
	done;
	@for file in systemd/system/*; do \
		service="$$(basename "$$file")"; \
		install -Dm0644 "$${file}" "${DESTDIR}/usr/lib/systemd/system/$${service}.d/apparmor.conf"; \
	done;
	@for file in systemd/user/*; do \
		service="$$(basename "$$file")"; \
		install -Dm0644 "$${file}" "${DESTDIR}/usr/lib/systemd/user/$${service}.d/apparmor.conf"; \
	done

local:
	@./configure --complain
	@make
	@sudo make install
	@sudo systemctl restart apparmor || sudo systemctl status apparmor

ABSTRACTIONS = $(shell find ${BUILD}/apparmor.d/abstractions/ -type f -printf "%P\n")
TUNABLES = $(shell find ${BUILD}/apparmor.d/tunables/ -type f -printf "%P\n")
$(P):
	@[ -f ${BUILD}/aa-log ] || exit 0; install -Dm755 ${BUILD}/aa-log ${DESTDIR}/usr/bin/aa-log
	@for file in ${ABSTRACTIONS}; do \
		install -Dm0644 "${BUILD}/apparmor.d/abstractions/$${file}" "${DESTDIR}/etc/apparmor.d/abstractions/$${file}"; \
	done;
	@for file in ${TUNABLES}; do \
		install -Dm0644 "${BUILD}/apparmor.d/tunables/$${file}" "${DESTDIR}/etc/apparmor.d/tunables/$${file}"; \
	done;
	@echo "Warning: profile dependencies fallback to unconfined."
	@for file in ${@}; do \
		grep 'rPx' "${BUILD}/apparmor.d/$${file}"; \
		sed -i -e "s/rPx/rPUx/g" "${BUILD}/apparmor.d/$${file}"; \
		install -Dvm0644 "${BUILD}/apparmor.d/$${file}" "${DESTDIR}/etc/apparmor.d/$${file}"; \
	done;
	@systemctl restart apparmor || systemctl status apparmor

dist ?= archlinux
package:
	@bash dists/build.sh ${dist}

pkg:
	@makepkg --syncdeps --install --cleanbuild --force --noconfirm

dpkg:
	@dch --newversion="${VERSION}" --urgency=medium --distribution=stable --controlmaint "Release ${VERSION}"
	@dpkg-buildpackage -b -d --no-sign
	@sudo dpkg -i "../apparmor.d_${VERSION}_all.deb"
	@make clean

rpm:
	@make local

lint:
	@shellcheck --shell=bash \
		PKGBUILD configure dists/build.sh \
		debian/${PKGNAME}.postinst debian/${PKGNAME}.postrm

clean:
	@rm -rf \
		debian/.debhelper debian/debhelper* debian/*.debhelper debian/${PKGNAME} \
		${PKGNAME}-*.pkg.tar.zst.sig ${PKGNAME}-*.pkg.tar.zst coverage.out \
		${PKGNAME}_*.* ${BUILD}
