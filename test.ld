ENTRY(start)

PHDRS {
    text PT_LOAD FILEHDR PHDRS;
}

SECTIONS {
    . = SIZEOF_HEADERS;
    PROVIDE(start = .);
    .text : { *(.text) } :text
    .data : { *(.data) } :text
}
