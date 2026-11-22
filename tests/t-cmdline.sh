# SPDX-License-Identifier: GPL-2.0-only
# Tests of grub.sh's kernel command line edits.
# Sourced by tests/run.sh, which defines eq, fails, $T, $P and $OSI.
# shellcheck shell=bash

# --- cmdline: add ----------------------------------------------------------------------------
eq "add to Ubuntu default" "quiet splash $P" "$(cmdline_add_pci "quiet splash")"
eq "add to empty" "$P" "$(cmdline_add_pci "")"
eq "add to spaces" "$P" "$(cmdline_add_pci "  ")"
eq "add keeps the quoted acpi_osi" "quiet splash console=tty0 $OSI $P" \
	"$(cmdline_add_pci "quiet splash console=tty0 $OSI")"
eq "add is idempotent" "quiet $P" "$(cmdline_add_pci "$(cmdline_add_pci quiet)")"
eq "add with param already present" "quiet $P splash" "$(cmdline_add_pci "quiet $P splash")"
eq "add merges another pci= option" "quiet pci=realloc,hpbussize=0x80,hpmmiosize=32M,hpmmioprefsize=32G" \
	"$(cmdline_add_pci "quiet pci=realloc")"
eq "add replaces a different value" "pci=hpbussize=0x80,realloc,hpmmiosize=32M,hpmmioprefsize=32G x" \
	"$(cmdline_add_pci "pci=hpbussize=0x20,realloc x")"
eq "add edits the last pci=" "pci=noaer a pci=realloc,$(echo "$P" | cut -d= -f2-) b" \
	"$(cmdline_add_pci "pci=noaer a pci=realloc b")"
eq "add keeps double spaces" "a  b $P" "$(cmdline_add_pci "a  b")"
eq "add ignores look-alikes" "nopci=1 xpci=2 $P" "$(cmdline_add_pci "nopci=1 xpci=2")"
eq "add to empty pci=" "a $P" "$(cmdline_add_pci "a pci=")"

# --- cmdline: remove -------------------------------------------------------------------------
eq "remove ours" "quiet splash" "$(cmdline_remove_pci "quiet splash $P")"
eq "remove from the middle" "quiet splash" "$(cmdline_remove_pci "quiet $P splash")"
eq "remove only" "" "$(cmdline_remove_pci "$P")"
eq "remove keeps others' options" "quiet pci=realloc" \
	"$(cmdline_remove_pci "quiet pci=realloc,hpbussize=0x80,hpmmiosize=32M,hpmmioprefsize=32G")"
eq "remove keeps a different value" "pci=hpbussize=0x20" "$(cmdline_remove_pci "pci=hpbussize=0x20")"
eq "remove when absent" "quiet splash $OSI" "$(cmdline_remove_pci "quiet splash $OSI")"
eq "remove from every pci=" "a b" "$(cmdline_remove_pci "a $P b $P")"
eq "remove round trip" "quiet splash console=tty0 $OSI" \
	"$(cmdline_remove_pci "$(cmdline_add_pci "quiet splash console=tty0 $OSI")")"
eq "remove round trip with realloc" "pci=realloc q" "$(cmdline_remove_pci "$(cmdline_add_pci "pci=realloc q")")"
eq "remove from empty" "" "$(cmdline_remove_pci "")"
