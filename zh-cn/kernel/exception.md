
在Linux 0.11 的代码树中，内核异常处理的服务程序分别是trap.c以及panic.c， trap.c 中通过中断将硬件的异常 分别做了处理，panic则实现了内核的异常处理接口。

上述中我们提到了中断和异常， 那么两者有什么异同呢？
从理论角度我们可以笼统的说中断是指的中央处理器(CPU)对系统发生某个事情后作出的一种反应，异常的定义没有明确的规定， 不通的体系架构的定义有一些差异，大体上基本认为异常是由于软件造成的。

一般情况下， 一个完整的可用操作系统由4部分组成。 分别是硬件、操作系统内核、操作系统服务以及用户应用程序。
当前tree 是Linus 基于 Intel 的386兼容机，其 CPU 为80386，想一下， 假如你是Linus， 你要为你的操作系统来适配386兼容机， 现在你要完成异常处理部分， 你应该做什么?
答案毋庸置疑吧， 所以具体关于中断和异常的处理我们来看看CPU手册中是如何描述的。那么我们按照一个正常开发流程去模拟当前Linus 是如何开发异常处理模块的。

## 80386

在i386的数据手册中， 有一章节描述了中断和异常。

原文是这么描述的:

The 80386 has two mechanisms for interrupting program execution:

    1. Exceptions are synchronous events that are the responses of the CPU to certain conditions detected during the execution of an instruction.
    2. Interrupts are asynchronous events.

    Interrupts and exceptions are alike in that both cause the processor to temporarily suspend its present program execution in order to execute a program of higher priority.
The major distinction between these two kinds of interrupts is their origin. An exception is always reproducible by re-executing with the program and data that caused the exception,
whereas an interrupt is generally independent of the currently executing program.

Application programmers are not normally concerned with servicing interrupts. More information on interrupts for systems programmers may be found in Chapter 9. Certain exceptions, however,are of interest to applications programmers,and many operating systems give applications programs the opportunity to service these exceptions. However,the operating system itself defines the interface between the applications programs and the exception mechanism of the 80386.

看手册挑重点， 我们来总结一下上述描述的一些关键点。

- 80386 为中断程序执行提供了两种机制
    - 异常是同步事件，在指令执行的过程中由CPU检测并响应。
    - 中断是异常事件，是由外部设备触发。
- 中断和异常异同点
    - 两者都会导致是的CPU暂停处理正在处理的任务，去处理优先级更高的任务。
    - 一个异常在执行导致异常的程序和数据的时候是可以被复制的。
    - 中断通常是独立于当前执行的程序的。
- 应用程序程序员通常不关心服务的中断。
- 应用程序程序员只需使用操作系统提供的应用接口， 这些接口的使用不当可能也会产生异常。

关于中断机制的详细内容， 本章节不在赘述。请阅读本书中断处理机制章节。

通过上述我们大抵了解了当前80386 实现了异常功能点。 那么我们继续阅读手册， 看详细的提供了哪些事件?

### 80386 异常向量表

|向量偏移值|描 述|说 明|
|:-----:|:----:|:----:|
|0|Devide Error| 当进行除以零的操作时产生|
|1|Debug Exceptions|当进行程序单步跟踪调试时， 设置了标志寄存器eflags的T标志时产生这个中断|
|2|NMI Interrupt|由不可屏蔽产生|
|3|Breakpoint|由断点指令INT3产生， 与Debug 处理相同|
|4|INTO Detected Overflow|eflags 的溢出标志0F引起|
|5|BOUND Range Exceeded|寻址到有效地址以外引起|
|6|Invalid Opcode|CPU执行发现一个无效的指令操作码|
|7|Coprocessor Not Available|设备不存在， 指协处理器。在两种情况下会产生该中断：a. CPU 遇到一个转意指令并且EM置位。(b)MP 和 TS 都在置位状态， CPU 遇到wait或一个转意指令。在这种情况下，处理程序在必要应该更新协处理器的状态|
|8|Double Exception|双故障出错|
|9|Coprocessor Segment Overrun|协处理器段超出|
|10|Invalid Task State Segment|CPU 切换时发现TSS无效|
|11|Segment Not Present|描述符所指的段不存在|
|12|Stack Fault|堆栈溢出或者不存在|
|13|General Protection|没有符合80386保护机制的(特权机制)操作引起|
|14|Page Fault|页溢出或不存在|
|15|(reserved)|保留位|
|16|Coprocessor Error|协处理器检测到非法操作|
|17-32|(reserved)|保留位|

上述表格便是80386手册中给出的所有的异常向量， 知道了每个异常的偏移地址，那么我们下面可以为内核写一个异常处理模块了，等等。 好像还少一点什么? 对，怎么访问向量表呢?

### 访问异常向量表

整个CPU 域地址空间的划分请参考内存管理章节。
通过上述章节我们可以很清晰的获取CPU 地址域的布局， 并且知道了异常向量的 Base Addr。

val = ;

### 设计对应的内核数据结构

有了访问地址，异常向量偏移，那么我们就可以设计代码框架了。我想当时Linus 应该是这么想的: 一直在研究Unix 操作系统设计，我想我也应该信号到我的操作系统中， 我可以把每个异常对应一个信号，用来做全局通知链，这样一些无需CPU reset解决的，可以做一下告警，告知开发应用程序或者驱动的程序员该如何规范使用当前芯片。 好吧，我要开干了！！！

### Linus 编写的异常代码

```
  1 /*
  2  *	linux/kernel/traps.c
  3  *
  4  *	(C) 1991  Linus Torvalds
  5  */
  6
  7 /*
  8  * 'Traps.c' handles hardware traps and faults after we have saved some
  9  * state in 'asm.s'. Currently mostly a debugging-aid， will be extended
 10  * to mainly kill the offending process (probably by giving it a signal，
 11  * but possibly by killing it outright if necessary).
 12  */
    /*
     * 在程序asm.s中保存了一些状态后，本程序用来处理硬件陷阱和故障。目前主要用于调试目的，
     * 以后将扩展用来杀死遭损坏的进程（主要是通过发送一个信号，但如果必要也会直接杀死）。
     */
 13 #include <string.h>	      // 字符串头文件。主要定义了一些有关内存或字符串操作的嵌入函数。
 14
 15 #include <linux/head.h>   // head头文件，定义了段描述符的简单结构，和几个选择符常量。
 16 #include <linux/sched.h>  // 调度程序头文件，定义了任务结构task_struct、初始任务0的数据，
			      // 还有一些有关描述符参数设置和获取的嵌入式汇编函数宏语句。
 17 #include <linux/kernel.h> // 内核头文件。含有一些内核常用函数的原形定义。
 18 #include <asm/system.h>   // 系统头文件。定义了设置或修改描述符/中断门等的嵌入式汇编宏。
 19 #include <asm/segment.h>  // 段操作头文件。定义了有关段寄存器操作的嵌入式汇编函数。
 20 #include <asm/io.h>	      // 输入/输出头文件。定义硬件端口输入/输出宏汇编语句。
 21
    // 以下语句定义了三个嵌入式汇编宏语句函数。有关嵌入式汇编的基本语法见本程序列表后的说明。
    // 用圆括号括住的组合语句（花括号中的语句）可以作为表达式使用，其中最后的__res是其输出值。
    // 第23行定义了一个寄存器变量__res。该变量将被保存在一个寄存器中，以便于快速访问和操作。
    // 如果想指定寄存器（例如eax），那么我们可以把该句写成“register char __res asm("ax");”。
    // 取段seg中地址addr处的一个字节。
    // 参数：seg - 段选择符；addr - 段内指定地址。
    // 输出：%0 - eax (__res)；输入：%1 - eax (seg)；%2 - 内存地址 (*(addr))。
 22 #define get_seg_byte(seg，addr) ({ \
 23 register char __res; \
 24 __asm__("push %%fs;mov %%ax，%%fs;movb %%fs:%2，%%al;pop %%fs" \
 25	    :"=a" (__res):"0" (seg)，"m" (*(addr))); \
 26 __res;})
 27
    // 取段seg中地址addr处的一个长字（4字节）。
    // 参数：seg - 段选择符；addr - 段内指定地址。
    // 输出：%0 - eax (__res)；输入：%1 - eax (seg)；%2 - 内存地址 (*(addr))。
 28 #define get_seg_long(seg，addr) ({ \
 29 register unsigned long __res; \
 30 __asm__("push %%fs;mov %%ax，%%fs;movl %%fs:%2，%%eax;pop %%fs" \
 31	    :"=a" (__res):"0" (seg)，"m" (*(addr))); \
 32 __res;})
 33
    // 取fs段寄存器的值（选择符）。
    // 输出：%0 - eax (__res)。
 34 #define _fs() ({ \
 35 register unsigned short __res; \
 36 __asm__("mov %%fs，%%ax":"=a" (__res):); \
 37 __res;})
 38
    // 以下定义了一些函数原型。
 39 void page_exception(void);			 // 页异常。实际是page_fault（mm/page.s，14）。
 40
 41 void divide_error(void);			 // int0（kernel/asm.s，20）。
 42 void debug(void);				 // int1（kernel/asm.s，54）。
 43 void nmi(void);				 // int2（kernel/asm.s，58）。
 44 void int3(void);				 // int3（kernel/asm.s，62）。
 45 void overflow(void);			 // int4（kernel/asm.s，66）。
 46 void bounds(void);				 // int5（kernel/asm.s，70）。
 47 void invalid_op(void);			 // int6（kernel/asm.s，74）。
 48 void device_not_available(void);		 // int7（kernel/sys_call.s，158）。
 49 void double_fault(void);			 // int8（kernel/asm.s，98）。
 50 void coprocessor_segment_overrun(void);	 // int9（kernel/asm.s，78）。
 51 void invalid_TSS(void);			 // int10（kernel/asm.s，132）。
 52 void segment_not_present(void);		 // int11（kernel/asm.s，136）。
 53 void stack_segment(void);			 // int12（kernel/asm.s，140）。
 54 void general_protection(void);		 // int13（kernel/asm.s，144）。
 55 void page_fault(void);			 // int14（mm/page.s，14）。
 56 void coprocessor_error(void);		 // int16（kernel/sys_call.s，140）。
 57 void reserved(void);			 // int15（kernel/asm.s，82）。
 58 void parallel_interrupt(void);		 // int39（kernel/sys_call.s，295）。
 59 void irq13(void);				 // int45 协处理器中断处理（kernel/asm.s，86）。
 60 void alignment_check(void);			 // int46（kernel/asm.s，148）。
 61
    // 该子程序用来打印出错中断的名称、出错号、调用程序的EIP、EFLAGS、ESP、fs段寄存器值、
    // 段的基址、段的长度、进程号pid、任务号、10字节指令码。如果堆栈在用户数据段，则还
    // 打印16字节的堆栈内容。这些信息可用于程序调试。
 62 static void die(char * str，long esp_ptr，long nr)
 63 {
 64	    long * esp = (long *) esp_ptr;
 65	    int i;
 66
 67	    printk("%s: %04x\n\r"，str，nr&0xffff);
    // 下行打印语句显示当前调用进程的CS:EIP、EFLAGS和SS:ESP的值。参照错误!未找到引用源。可知，这里esp[0]
    // 即为图中的esp0位置。因此我们把这句拆分开来看为：
    // (1) EIP:\t%04x:%p\n  -- esp[1]是段选择符（cs），esp[0]是eip
    // (2) EFLAGS:\t%p	    -- esp[2]是eflags
    // (3) ESP:\t%04x:%p\n  -- esp[4]是原ss，esp[3]是原esp
 68	    printk("EIP:\t%04x:%p\nEFLAGS:\t%p\nESP:\t%04x:%p\n"，
 69		    esp[1]，esp[0]，esp[2]，esp[4]，esp[3]);
 70	    printk("fs: %04x\n"，_fs());
 71	    printk("base: %p， limit: %p\n"，get_base(current->ldt[1])，get_limit(0x17));
 72	    if (esp[4] == 0x17) {	      // 若原ss值为0x17（用户栈），则还打印出
 73		    printk("Stack: ");	      // 用户栈中的4个长字值（16字节）。
 74		    for (i=0;i<4;i++)
 75			    printk("%p "，get_seg_long(0x17，i+(long *)esp[3]));
 76		    printk("\n");
 77	    }
 78	    str(i);		    // 取当前运行任务的任务号（include/linux/sched.h，210行）。
 79	    printk("Pid: %d， process nr: %d\n\r"，current->pid，0xffff & i); // 进程号，任务号。
 80	    for(i=0;i<10;i++)
 81		    printk("%02x "，0xff & get_seg_byte(esp[1]，(i+(char *)esp[0])));
 82	    printk("\n\r");
 83	    do_exit(11);	    /* play segment exception */
 84 }
 85
    // 以下这些以do_开头的函数是asm.s中对应中断处理程序调用的C函数。
 86 void do_double_fault(long esp， long error_code)
 87 {
 88	    die("double fault"，esp，error_code);
 89 }
 90
 91 void do_general_protection(long esp， long error_code)
 92 {
 93	    die("general protection"，esp，error_code);
 94 }
 95
 96 void do_alignment_check(long esp， long error_code)
 97 {
 98	die("alignment check"，esp，error_code);
 99 }
100
101 void do_divide_error(long esp， long error_code)
102 {
103	    die("divide error"，esp，error_code);
104 }
105
    // 参数是进入中断后被顺序压入堆栈的寄存器值。参见asm.s程序第24--35行。
106 void do_int3(long * esp， long error_code，
107		    long fs，long es，long ds，
108		    long ebp，long esi，long edi，
109		    long edx，long ecx，long ebx，long eax)
110 {
111	    int tr;
112
113	    __asm__("str %%ax":"=a" (tr):"" (0));		// 取任务寄存器值ètr。
114	    printk("eax\t\tebx\t\tecx\t\tedx\n\r%8x\t%8x\t%8x\t%8x\n\r"，
115		    eax，ebx，ecx，edx);
116	    printk("esi\t\tedi\t\tebp\t\tesp\n\r%8x\t%8x\t%8x\t%8x\n\r"，
117		    esi，edi，ebp，(long) esp);
118	    printk("\n\rds\tes\tfs\ttr\n\r%4x\t%4x\t%4x\t%4x\n\r"，
119		    ds，es，fs，tr);
120	    printk("EIP: %8x   CS: %4x	EFLAGS: %8x\n\r"，esp[0]，esp[1]，esp[2]);
121 }
122
123 void do_nmi(long esp， long error_code)
124 {
125	    die("nmi"，esp，error_code);
126 }
127
128 void do_debug(long esp， long error_code)
129 {
130	    die("debug"，esp，error_code);
131 }
132
133 void do_overflow(long esp， long error_code)
134 {
135	    die("overflow"，esp，error_code);
136 }
137
138 void do_bounds(long esp， long error_code)
139 {
140	    die("bounds"，esp，error_code);
141 }
142
143 void do_invalid_op(long esp， long error_code)
144 {
145	    die("invalid operand"，esp，error_code);
146 }
147
148 void do_device_not_available(long esp， long error_code)
149 {
150	    die("device not available"，esp，error_code);
151 }
152
153 void do_coprocessor_segment_overrun(long esp， long error_code)
154 {
155	    die("coprocessor segment overrun"，esp，error_code);
156 }
157
158 void do_invalid_TSS(long esp，long error_code)
159 {
160	    die("invalid TSS"，esp，error_code);
161 }
162
163 void do_segment_not_present(long esp，long error_code)
164 {
165	    die("segment not present"，esp，error_code);
166 }
167
168 void do_stack_segment(long esp，long error_code)
169 {
170	    die("stack segment"，esp，error_code);
171 }
172
173 void do_coprocessor_error(long esp， long error_code)
174 {
175	    if (last_task_used_math != current)
176		    return;
177	    die("coprocessor error"，esp，error_code);
178 }
179
180 void do_reserved(long esp， long error_code)
181 {
182	    die("reserved (15，17-47) error"，esp，error_code);
183 }
184
    // 下面是异常（陷阱）中断程序初始化子程序。设置它们的中断调用门（中断向量）。
    // set_trap_gate()与set_system_gate()都使用了中断描述符表IDT中的陷阱门（Trap Gate），
    // 它们之间的主要区别在于前者设置的特权级为0，后者是3。因此断点陷阱中断int3、溢出中断
    // overflow 和边界出错中断 bounds 可以由任何程序调用。 这两个函数均是嵌入式汇编宏程序，
    // 参见include/asm/system.h，第36行、39行。
185 void trap_init(void)
186 {
187	    int i;
188
189	    set_trap_gate(0，&divide_error);	 // 设置除操作出错的中断向量值。以下雷同。
190	    set_trap_gate(1，&debug);
191	    set_trap_gate(2，&nmi);
192	    set_system_gate(3，&int3);		 /* int3-5 can be called from all */
193	    set_system_gate(4，&overflow);	 /* int3-5 可以被所有程序执行 */
194	    set_system_gate(5，&bounds);
195	    set_trap_gate(6，&invalid_op);
196	    set_trap_gate(7，&device_not_available);
197	    set_trap_gate(8，&double_fault);
198	    set_trap_gate(9，&coprocessor_segment_overrun);
199	    set_trap_gate(10，&invalid_TSS);
200	    set_trap_gate(11，&segment_not_present);
201	    set_trap_gate(12，&stack_segment);
202	    set_trap_gate(13，&general_protection);
203	    set_trap_gate(14，&page_fault);
204	    set_trap_gate(15，&reserved);
205	    set_trap_gate(16，&coprocessor_error);
206	    set_trap_gate(17，&alignment_check);

    // 下面把int17-47的陷阱门先均设置为reserved，以后各硬件初始化时会重新设置自己的陷阱门。
207	    for (i=18;i<48;i++)
208		    set_trap_gate(i，&reserved);

    // 设置协处理器中断0x2d（45）陷阱门描述符，并允许其产生中断请求。设置并行口中断描述符。
209	    set_trap_gate(45，&irq13);
210	    outb_p(inb_p(0x21)&0xfb，0x21);	     // 允许8259A主芯片的IRQ2中断请求。
211	    outb(inb_p(0xA1)&0xdf，0xA1);	     // 允许8259A从芯片的IRQ13中断请求。
212	    set_trap_gate(39，&parallel_interrupt);  // 设置并行口1的中断0x27陷阱门描述符。
213 }
214
```

### panic

异常接口已经处理完毕，基本上触发上述事件，都有做处理。等等，假如出现很严重的事情怎么办呢？已经完全影响系统的关键部件的完整度了。 Linus 当时可能是这么想的:  我需要做一些事情，告知系统以及管理员，告知他们操作系统挂掉了，好吧，我先简单做一个接口吧，起个什么名字呢？ panic， 这个名字好像不错，就叫它吧。  接口我先简单处理一下，假如我发现当前进程是0号进程，那么我就认为操作系统还没有挂载文件系统，是swapper进程出错了，反之不是的话我需要同步一下文件系统，然后制造死机吧(死循环)。

### Linus 编写的panic 代码

```
  1 /*
  2  *	linux/kernel/panic.c
  3  *
  4  *	(C) 1991  Linus Torvalds
  5  */
  6
  7 /*
  8  * This function is used through-out the kernel (includeinh mm and fs)
  9  * to indicate a major problem.
 10  */
    /*
     * 该函数在整个内核中使用（包括在 头文件*.h， 内存管理程序mm和文件系统fs中），
     * 用以指出主要的出错问题。
     */
 11 #include <linux/kernel.h> // 内核头文件。含有一些内核常用函数的原形定义。
 12 #include <linux/sched.h>  // 调度程序头文件，定义了任务结构task_struct、初始任务0的数据，
			      // 还有一些有关描述符参数设置和获取的嵌入式汇编函数宏语句。
 13
 14 void sys_sync(void);    /* it is really int */ /* 实际上是整型int (fs/buffer.c，44) */
 15
    // 该函数用来显示内核中出现的重大错误信息，并运行文件系统同步函数，然后进入死循环--死机。
    // 如果当前进程是任务0的话，还说明是交换任务出错，并且还没有运行文件系统同步函数。
    // 函数名前的关键字volatile用于告诉编译器gcc该函数不会返回。这样可让gcc产生更好一些的
    // 代码，更重要的是使用这个关键字可以避免产生某些（未初始化变量的）假警告信息。
    // 等同于现在gcc的函数属性说明：void panic(const char *s) __attribute__ ((noreturn));
 16 volatile void panic(const char * s)
 17 {
 18	    printk("Kernel panic: %s\n\r"，s);
 19	    if (current == task[0])
 20		    printk("In swapper task - not syncing\n\r");
 21	    else
 22		    sys_sync();
 23	    for(;;);
 24 }
 25

```

### 测试

代码写完了，按照软件开发流程，下面就需要测试了， 让我们编写测试例触发上述异常(有的无法触发需要硬件配置)，来验证效果吧。
由于篇幅较长， 本书这里只简单演示一个测试用例， 更多的测试用例，请在本书所带的资料中获取(直播素材)。

我们来验证堆栈溢出后内核发生什么？

测试例代码

```

```

编译

运行

结果

### 在线协作

BitKeeper 是垃圾，先忍忍吧，现在贡献的人还不是很多，等我有空我会在开发一个协作工具。

### 参考

>  [INTEL 80386 PROGRAMMER'S REFERENCE MANUAL 1986](http://css.csail.mit.edu/6.858/2013/readings/i386.pdf)
>  [Linux 内核完全注释 - 赵炯](http://oldlinux.org/book.html)
