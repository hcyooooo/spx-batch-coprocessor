ENTRY(_start)

MEMORY
{
  ram (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{
  . = ORIGIN(ram);

  .text : ALIGN(4)
  {
    KEEP(*(.init))
    *(.text*)
    *(.rodata*)
  } > ram

  . = ALIGN(16);
  .data :
  {
    *(.sdata*)
    *(.data*)
  } > ram

  . = ALIGN(16);
  .bss (NOLOAD) :
  {
    __bss_start = .;
    *(.sbss*)
    *(.bss*)
    *(COMMON)
    __bss_end = .;
  } > ram

  . = ALIGN(16);
  __stack_top = ORIGIN(ram) + 0x0000f000;
  __smoke_magic_addr = 0x0000fffc;
}

PROVIDE(__global_pointer$ = 0);
