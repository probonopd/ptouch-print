# P-touch Utility

A small GNUstep GUI for printing labels with Brother P-touch printers.

- Native GNUstep/AppKit rendering
- Live preview and Save-to-PNG.
- Automatic printer/tape detection: the app disables the **Print** button when the door is open or no tape is present and re-queries tape info after the door closes.

Build

- Requires GNUstep development packages and libusb.
- Build: `gmake`.

Run

- Start the GUI from the project root:
  `./PtouchUtility.app/PtouchUtility`
- Run from a terminal to see status/debug messages.

Tools
- `ptouch-utility`: CLI tool for label printing.

- `obj/status-monitor` — poll and log printer status bytes for debugging.
- `obj/render-test` — automated rendering tests.

Troubleshooting

- If the printer isn't found, the app shows "Printer not connected"; check USB and that the device is switched to position E.
- For verbose debug logs, use the CLI tools' `-v/--verbose` flags or run the GUI from a terminal.

License

- GPLv3, based on https://dominic.familie-radermacher.ch/projekte/ptouch-print/
