# 异常处理

在 Linux 0.11 的代码树中，内核异常处理的服务程序分别是 trap.c 和 panic.c，trap.c 负责处理硬件异常，panic.c 则实现了内核的异常处理接口。

上面提到了中断和异常，那么两者有什么异同呢？

从理论的角度我们可以笼统的说中断是指中央处理器（CPU）对系统发生某个事情后作出的一种反应，异常的定义没有明确的规定，不同的体系架构的定义有一些差异，不过大体上可以认为异常是由于软件造成的。

一般情况下，一个完整的可用操作系统由 4 部分组成。分别是硬件、操作系统内核、操作系统服务以及用户应用程序。

当前 Linux 0.11 代码树是 Linus 基于 Intel 的 386 兼容机编写的。其 CPU 为80386，想一下，假如你是 Linus，你要为你的操作系统来适配 386 兼容机，现在你要完成异常处理部分，你应该做什么？

答案毋庸置疑吧，所以具体关于中断和异常的处理我们来看看 CPU 手册中是如何描述的。那么，我们先按照一个正常开发流程去模拟当前 Linus 是如何开发异常处理模块的。

## 80386

在 i386 的数据手册中，有一章节描述了中断和异常。

原文是这么描述的:

> The 80386 has two mechanisms for interrupting program execution:
>
>     1. Exceptions are synchronous events that are the responses of the CPU to
> 	certain conditions detected during the execution of an instruction.
>
>     2. Interrupts are asynchronous events.
>
> Interrupts and exceptions are alike in that both cause the processor to temporarily suspend its present program execution in order to execute a program of higher priority.
>
> The major distinction between these two kinds of interrupts is their origin. An exception is always reproducible by re-executing with the program and data that caused the exception, whereas an interrupt is generally independent of the currently executing program.
>
> Application programmers are not normally concerned with servicing interrupts. More information on interrupts for systems programmers may be found in Chapter 9. Certain exceptions, however,are of interest to applications programmers,and many operating systems give applications programs the opportunity to service these exceptions. However,the operating system itself defines the interface between the applications programs and the exception mechanism of the 80386.

看手册找重点，我们来总结一下上述描述的一些关键点。

- 80386 为中断程序执行提供了两种机制
    - 异常是同步事件，用于响应指令执行过程检测到的特定条件。
    - 中断是异常事件，是由外部设备触发。

- 中断和异常异同点
    - 两者都会导致的是：CPU 暂停当前程序的执行，去处理优先级更高的程序。
    - 异常可以重复触发，只要用同样的程序和数据反复执行。
    - 中断则不然，它通常是独立于当前执行的程序的。

- 应用开发人员通常不关心服务的中断。
- 应用开发人员只需使用操作系统提供的应用接口，这些接口的使用不当可能也会产生异常。

关于中断机制的详细内容，本章节不再赘述。请阅读本书中断处理机制章节内容。

上面大抵描述了 80386 的异常和中断概念。接下来继续阅读手册，看看 80386 到底提供了哪些详细的异常事件?

## 80386 异常向量表

|向量偏移值|描 述|说 明|
|:-----:|:----:|:----:|
|0|Devide Error| 当进行除以零的操作时产生|
|1|Debug Exceptions|当进行程序单步跟踪调试时，设置了标志寄存器 eflags 的T标志时产生这个中断|
|2|NMI Interrupt|由不可屏蔽产生|
|3|Breakpoint|由断点指令INT3产生，与 Debug 处理相同|
|4|INTO Detected Overflow| eflags 的溢出标志 0F 引起|
|5|BOUND Range Exceeded|寻址到有效地址以外引起|
|6|Invalid Opcode|CPU执行发现一个无效的指令操作码|
|7|Coprocessor Not Available|设备不存在，指协处理器。在两种情况下会产生该中断：a：CPU 遇到一个转意指令并且EM置位。b：MP 和 TS 都在置位状态， CPU 遇到wait或一个转意指令。在这种情况下，处理程序在必要应该更新协处理器的状态|
|8|Double Exception|双故障出错|
|9|Coprocessor Segment Overrun|协处理器段超出|
|10|Invalid Task State Segment|CPU 切换时发现 TSS 无效|
|11|Segment Not Present|描述符所指的段不存在|
|12|Stack Fault|堆栈溢出或者不存在|
|13|General Protection|没有符合 80386 保护机制的(特权机制)操作引起|
|14|Page Fault|页溢出或不存在|
|15|(reserved)|保留位|
|16|Coprocessor Error|协处理器检测到非法操作|
|17-32|(reserved)|保留位|

上述表格便是 80386 手册中给出的所有异常向量，知道了每个异常的偏移地址，那么下面可以为内核写一个异常处理模块了，等等。好像还少一点什么？对，怎么访问向量表呢？

## 访问异常向量表

整个 CPU 域地址空间的划分请参考内存管理章节。

通过上述章节我们可以很清晰的获取 CPU 地址域的布局，并且知道了异常向量的 Base Addr。

```
val = ;

```

## 设计对应的内核数据结构

有了访问地址，异常向量偏移，那么我们就可以设计代码框架了。我想当时 Linus 应该是这么想的：我一直在研究 Unix 操作系统设计，所以我是否也可以将信号用到 Linux 操作系统中呢，可以把每个异常对应一个信号，用来做全局通知链，这样一些无需 CPU reset 解决的，可以做一下告警，告知开发应用程序或者驱动的程序员该如何规范使用当前芯片。好吧，我要开干了！！！

## Linus 编写的异常代码

```
/*
 *  linux/kernel/traps.c
 *
 *  (C) 1991  Linus Torvalds
 */

/*
 * 'Traps.c' handles hardware traps and faults after we have saved some
 * state in 'asm.s'. Currently mostly a debugging-aid, will be extended
 * to mainly kill the offending process (probably by giving it a signal,
 * but possibly by killing it outright if necessary).
 */

/* 我们保存了一些硬件状态在'asm.s'中，然后我们使用'Traps.c'用来处理陷进和故障。当前主要用于调试，
 * 后续我们将扩展使其可以杀死一些令人厌恶的进程（或许可以给它一个信号，但是尽量还是将其杀死）。
 */

#include <string.h>

#include <linux/head.h>
#include <linux/sched.h>
#include <linux/kernel.h>
#include <asm/system.h>
#include <asm/segment.h>
#include <asm/io.h>

/* 以下语句定义了三个嵌入式汇编宏语句函数，有关嵌入式汇编的基本语法见本程序列表后的说明。
 * 用圆括号括住的组合语句（花括号中的语句）可以作为表达式使用,其中最后的__res是其输出值。
 * 第23行定义了一个寄存器变量__res，该变量将被保存在一个寄存器中，以便于快速访问和操作。
 * 如果想指定寄存器（例如eax），那么我们可以把该句写成register char __res asm("ax")；
 * 取段seg中地址addr处的一个字节。
 * 参数：seg - 段选择符；addr - 段内指定地址。
 * 输出：%0 - eax (__res)；输入：%1 - eax (seg)；%2 - 内存地址 (*(addr))
 */

#define get_seg_byte(seg,addr) ({ \
register char __res; \
__asm__("push %%fs;mov %%ax,%%fs;movb %%fs:%2,%%al;pop %%fs" \
	:"=a" (__res):"0" (seg),"m" (*(addr))); \
__res;})

/* 取段seg中地址addr处的一个长字（4字节）。
 * 参数：seg - 段选择符；addr - 段内指定地址。
 * 输出：%0 - eax (__res)；输入：%1 - eax (seg)；%2 - 内存地址 (*(addr))
 */

#define get_seg_long(seg,addr) ({ \
register unsigned long __res; \
__asm__("push %%fs;mov %%ax,%%fs;movl %%fs:%2,%%eax;pop %%fs" \
	:"=a" (__res):"0" (seg),"m" (*(addr))); \
__res;})

/* 取fs段寄存器的值(选择符)
 * 输出：%0 - eax (__res
 */

#define _fs() ({ \
register unsigned short __res; \
__asm__("mov %%fs,%%ax":"=a" (__res):); \
__res;})

/* 下面是异常向量表对应的函数原型 */

int do_exit(long code);

void page_exception(void);

void divide_error(void);
void debug(void);
void nmi(void);
void int3(void);
void overflow(void);
void bounds(void);
void invalid_op(void);
void device_not_available(void);
void double_fault(void);
void coprocessor_segment_overrun(void);
void invalid_TSS(void);
void segment_not_present(void);
void stack_segment(void);
void general_protection(void);
void page_fault(void);
void coprocessor_error(void);
void reserved(void);
void parallel_interrupt(void);
void irq13(void);

/* die 函数主要用于打印出错的中断的名称、出错号、调用程序的EIP、EFLAGS、ESP、fs
 * 段寄存器值以及段的基址、段的长度、进程号pid、任务号、10字节指令码。
 * 如果堆栈在用户数据段，则还打印16字节的堆栈内容。
 */

static void die(char * str,long esp_ptr,long nr)
{
	long * esp = (long *) esp_ptr;
	int i;

	printk("%s: %04x\n\r",str,nr&0xffff);
	printk("EIP:\t%04x:%p\nEFLAGS:\t%p\nESP:\t%04x:%p\n",
		esp[1],esp[0],esp[2],esp[4],esp[3]);
	printk("fs: %04x\n",_fs());
	printk("base: %p, limit: %p\n",get_base(current->ldt[1]),get_limit(0x17));
	if (esp[4] == 0x17) {
		printk("Stack: ");
		for (i=0;i<4;i++)
			printk("%p ",get_seg_long(0x17,i+(long *)esp[3]));
		printk("\n");
	}
	str(i);
	printk("Pid: %d, process nr: %d\n\r",current->pid,0xffff & i);
	for(i=0;i<10;i++)
		printk("%02x ",0xff & get_seg_byte(esp[1],(i+(char *)esp[0])));
	printk("\n\r");
	do_exit(11);		/* play segment exception */
}

/* 以下这些以 do_ 开头的函数是 asm.s 中对应中断处理程序调用的C函数。

void do_double_fault(long esp, long error_code)
{
	die("double fault",esp,error_code);
}

void do_general_protection(long esp, long error_code)
{
	die("general protection",esp,error_code);
}

void do_divide_error(long esp, long error_code)
{
	die("divide error",esp,error_code);
}

void do_int3(long * esp, long error_code,
		long fs,long es,long ds,
		long ebp,long esi,long edi,
		long edx,long ecx,long ebx,long eax)
{
	int tr;

	__asm__("str %%ax":"=a" (tr):"0" (0));
	printk("eax\t\tebx\t\tecx\t\tedx\n\r%8x\t%8x\t%8x\t%8x\n\r",
		eax,ebx,ecx,edx);
	printk("esi\t\tedi\t\tebp\t\tesp\n\r%8x\t%8x\t%8x\t%8x\n\r",
		esi,edi,ebp,(long) esp);
	printk("\n\rds\tes\tfs\ttr\n\r%4x\t%4x\t%4x\t%4x\n\r",
		ds,es,fs,tr);
	printk("EIP: %8x   CS: %4x  EFLAGS: %8x\n\r",esp[0],esp[1],esp[2]);
}

void do_nmi(long esp, long error_code)
{
	die("nmi",esp,error_code);
}

void do_debug(long esp, long error_code)
{
	die("debug",esp,error_code);
}

void do_overflow(long esp, long error_code)
{
	die("overflow",esp,error_code);
}

void do_bounds(long esp, long error_code)
{
	die("bounds",esp,error_code);
}

void do_invalid_op(long esp, long error_code)
{
	die("invalid operand",esp,error_code);
}

void do_device_not_available(long esp, long error_code)
{
	die("device not available",esp,error_code);
}

void do_coprocessor_segment_overrun(long esp, long error_code)
{
	die("coprocessor segment overrun",esp,error_code);
}

void do_invalid_TSS(long esp,long error_code)
{
	die("invalid TSS",esp,error_code);
}

void do_segment_not_present(long esp,long error_code)
{
	die("segment not present",esp,error_code);
}

void do_stack_segment(long esp,long error_code)
{
	die("stack segment",esp,error_code);
}

void do_coprocessor_error(long esp, long error_code)
{
	if (last_task_used_math != current)
		return;
	die("coprocessor error",esp,error_code);
}

void do_reserved(long esp, long error_code)
{
	die("reserved (15,17-47) error",esp,error_code);
}

/* trap_init 函数是异常（陷阱）中断程序初始化子程序，主要设置它们的中断向量表。
 * set_trap_gate() 与 set_system_gate() 都使用了中断描述符表IDT中的陷阱门（Trap Gate）
 * 它们之间的主要区别在于前者设置的特权级为0，后者是3。因此断点陷阱中断int3、溢出中断
 * overflow 和边界出错中断 bounds 可以由任何程序调用。这两个函数均是嵌入式汇编宏程序。
 * 更多可以查看 include/asm/system.h；第36行以及39行。
 */

void trap_init(void)
{
	int i;

	set_trap_gate(0,&divide_error);
	set_trap_gate(1,&debug);
	set_trap_gate(2,&nmi);
	set_system_gate(3,&int3);	/* int3-5 can be called from all */
	set_system_gate(4,&overflow);
	set_system_gate(5,&bounds);
	set_trap_gate(6,&invalid_op);
	set_trap_gate(7,&device_not_available);
	set_trap_gate(8,&double_fault);
	set_trap_gate(9,&coprocessor_segment_overrun);
	set_trap_gate(10,&invalid_TSS);
	set_trap_gate(11,&segment_not_present);
	set_trap_gate(12,&stack_segment);
	set_trap_gate(13,&general_protection);
	set_trap_gate(14,&page_fault);
	set_trap_gate(15,&reserved);
	set_trap_gate(16,&coprocessor_error);
	for (i=17;i<48;i++)
		set_trap_gate(i,&reserved);
	set_trap_gate(45,&irq13);
	outb_p(inb_p(0x21)&0xfb,0x21);
	outb(inb_p(0xA1)&0xdf,0xA1);
	set_trap_gate(39,&parallel_interrupt);
}
```

## panic

异常接口已经处理完毕，基本上触发上述事件，都有做处理。等等，假如出现很严重的事情怎么办呢？已经完全影响系统的关键部件的完整度了。Linus 当时可能是这么想的：我需要做一些事情，告知系统以及管理员，告知他们操作系统挂掉了，好吧，我先简单做一个接口吧，起个什么名字呢？panic，这个名字好像不错，就叫它吧。接口我先简单处理一下，假如我发现当前进程是 0 号进程，那么我就认为操作系统还没有挂载文件系统，是 swapper 进程出错了，反之不是的话我需要同步一下文件系统，然后制造死机吧（死循环）。

## Linus 编写的panic 代码

```
/*
 *  linux/kernel/panic.c
 *
 *  (C) 1991  Linus Torvalds
 */

/*
 * This function is used through-out the kernel (includeinh mm and fs)
 * to indicate a major problem.
 */
#define PANIC

#include <linux/kernel.h>
#include <linux/sched.h>

void sys_sync(void);	/* it's really int */

/* panic 函数用来打印内核中出现的重大错误信息，并运行文件系统同步函数，然后进入死循环。
 * 如果当前进程是任务0的话，还说明是交换任务出错，并且还没有运行文件系统同步函数。
 * 函数名前的关键字 volatile 用于告诉编译器 gcc 该函数不会返回。这样可让 gcc 产生更好一些的
 * 代码，更重要的是使用这个关键字可以避免产生某些（未初始化变量的）假警告信息。
 * 等同于现在gcc的函数属性说明：void panic(const char *s) __attribute__ ((noreturn));
 */

void panic(const char * s)
{
	printk("Kernel panic: %s\n\r",s);
	if (current == task[0])
		printk("In swapper task - not syncing\n\r");
	else
		sys_sync();
	for(;;);
}
```

## 测试

代码写完了，按照软件开发流程，下面就需要测试了，让我们编写测试用例触发上述异常（有的无法触发需要硬件配置），来验证效果吧。
由于篇幅较长，本书这里只简单演示一个测试用例，更多的测试用例，请在本书所带的资料中获取。

我们来验证堆栈溢出后内核发生什么？

### 测试代码

```

```

### 编译

### 运行

### 结果


## 在线协作

BitKeeper 是垃圾，先忍忍吧，现在贡献的人还不是很多，等我有空我会在开发一个协作工具。

## 参考资料

- INTEL 80386 PROGRAMMER'S REFERENCE MANUAL 1986
- Linux 内核完全注释, 赵炯, 机械工业出版社, 2004
