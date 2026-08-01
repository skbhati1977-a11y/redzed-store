REDZED UPM V757.5 — SINGLE CONFIRMATION CONTEXT FIX

VERIFIED
========
This is not a Bulk payload.

The base V729 marks a single Colour as "full available Lot" when that
Colour is the only currently OPEN/assignable Colour.

Example:
Selected = C3
Available = C3
Therefore base full = true

But assignment rows still contain only C3.

ONLY FIXED
==========
Single Colour row confirmation text and context:

CONFIRM COLOUR ASSIGNMENT

क्या आप पूरा Colour C3 assign करना चाहते हैं?
Department: Print
Worker: Sanju · WRK-...
Colour: C3
Sizes: L 26 · XL 26 · XXL 26

CANCEL
YES · ASSIGN C3

BULK ASSIGN
===========
Bulk confirmation and Bulk logic are untouched.

INSTALL
=======
Replace:
real-universal-production-v757-final-approved.js

HTML:
<script src="real-universal-production-v757-final-approved.js?v=7575"></script>

Console:
V757_5_SINGLE_CONFIRMATION_CONTEXT_FIX
