INCLUDE memory.ld

EXTERN(_EXCEPTIONS);
EXTERN(_INTERRUPTS);

EXTERN(_reset);
EXTERN(_defaultHandler);

PROVIDE(_nmi = _defaultHandler);
PROVIDE(_hardFault = _defaultHandler);
PROVIDE(_memManageFault = _defaultHandler);
PROVIDE(_busFault = _defaultHandler);
PROVIDE(_usageFault = _defaultHandler);
PROVIDE(_svCall = _defaultHandler);
PROVIDE(_debugMonitor = _defaultHandler);
PROVIDE(_pendSv = _defaultHandler);
PROVIDE(_sysTick = _defaultHandler);

ENTRY(_reset);

SECTIONS
{
  PROVIDE(_stack_start = ORIGIN(RAM) + LENGTH(RAM));

  .vector_table ORIGIN(FLASH) :
  {
    LONG(_stack_start);
    KEEP(*(.vector_table.exceptions)); /* _EXCEPTIONS */
    KEEP(*(.vector_table.interrupts)); /* _INTERRUPTS */
  } > FLASH

  PROVIDE(_stext = ADDR(.vector_table) + SIZEOF(.vector_table));

  .text _stext :
  {
    *(.text._reset);
    *(.text .text.*);
    . = ALIGN(4);
    _etext = .;
  } > FLASH

  .rodata : ALIGN(4)
  {
    . = ALIGN(4);
    _srodata = .;
    *(.rodata .rodata.*);
    . = ALIGN(4);
    _erodata = .;
  } > FLASH

  .data : ALIGN(4)
  {
    . = ALIGN(4);
    _sdata = .;
    *(.data .data.*);
    . = ALIGN(4);
    _edata = .;
  } > RAM AT>FLASH

  _sidata = LOADADDR(.data);

  .bss (NOLOAD) : ALIGN(4)
  {
    . = ALIGN(4);
    _sbss = .;
    *(.bss .bss.*);
    *(COMMON); /* C statics */
    . = ALIGN(4);
    _ebss = .;
  } > RAM

  .uninit (NOLOAD) : ALIGN(4)
  {
    . = ALIGN(4);
    _suninit = .;
    *(.uninit .uninit.*);
    . = ALIGN(4);
    _euninit = .;
  } > RAM

  /DISCARD/ :
  {
    *(.ARM.exidx);
    *(.ARM.exidx.*);
    *(.ARM.extab.*);
  }
}

