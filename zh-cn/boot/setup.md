	.code16
#
# setup.s 是一个操作系统加载程序，利用ROM BIOS中断读取机器系统数据，
# 这段代码查询bios有关内存/磁盘/其它参数，并将这些数据保存到0x90000
# 开始的位置(从0x90000-0x901FF，也就是原来bootsect代码的地方)。
# 然后setup程序将system模块从0x10000~0x8ffff(512KB)整块向下移动到
#	内存的绝对地址0x00000处，然后加载中断描述符表寄存器(idtr)和全局
# 描述符表寄存器(gdtr)，开启A20地址线，重新设置两个中断控制芯片8259A，
# 将硬件终端号重新设置成为0x20~0x2f,最后设置CPU的控制寄存器CR0，进入
# 到32位保护模式运行，并跳转到system模块的head.s程序继续运行。


					--------------------
					-      。。。      -
					-------------------- -----	
					-   数据段描述符   -   |临时全局描述符表(gdt) 
					--------------------   |
					-   代码段描述符   -   |
					-------------------- -----
					-   setup.S代码    -
					-------------------- 0x90200
					-   系统参数       -
					-------------------- 0x90000
					-     。。。       -
					--------------------   --------------
					-    库模块        -          |
					--------------------          |  system模块 
					-   内存管理模块   -          | 
					--------------------          |
					-    内核模块      -          |
					--------------------          |
					-    main.c        -          |
					--------------------          |
					-     head.S       -          |
					--------------------          |
					-------------------- 0x00000 -------- 
					
					
	.equ INITSEG, 0x9000	# 原来bootsect所处的段
	.equ SYSSEG, 0x1000	# system loaded at 0x10000 (65536).
	.equ SETUPSEG, 0x9020	# 本程序的段地址

	.global _start, begtext, begdata, begbss, endtext, enddata, endbss
	.text
	begtext:
	.data
	begdata:
	.bss
	begbss:
	.text

	ljmp $SETUPSEG, $_start	
_start:

#  整个读磁盘的过程都很顺利，现在将光标位置保存以备后用
#  将DS设置成INITSEG(0x9000)
	mov	$INITSEG, %ax	# this is done in bootsect already, but...
	mov	%ax, %ds
# 调用系统中断0x10读取光标位置。下面是中断前的准备和调用中断
	mov	$0x03, %ah	# read cursor pos
	xor	%bh, %bh
	int	$0x10		# save it in known place, con_init fetches
	mov	%dx, %ds:0	# it from 0x90000. 将信息保存在0x90000处，控制台初始化时来读取。
# Get memory size (extended mem, kB)
# 获取扩展内存大小，调用中断0x15，功能号ah：0x88，同时将得到扩展内存保存到0x90002
	mov	$0x88, %ah 
	int	$0x15
	mov	%ax, %ds:2

# Get video-card data:
# 下面代码用于取得的是当前的显卡的显示模式。调用中断0x10，功能号ah：0xf。
# 0x90004存放当前页，0x90006显示模式，0x90007字符列数

	mov	$0x0f, %ah
	int	$0x10
	mov	%bx, %ds:4	# bh = display page
	mov	%ax, %ds:6	# al = video mode, ah = window width

# check for EGA/VGA and some config parameters
# 检查显示模式。并取得参数。其中ega和vga是显示器的两种模式。
# 利用中断0x10来实现读取信息，并将相关信息保存。
# 0x9000A存放显存大小，0x9000B显示状态(彩色还是单色)，
# 0x9000C显卡的特征参数

	mov	$0x12, %ah
	mov	$0x10, %bl
	int	$0x10
	mov	%ax, %ds:8
	mov	%bx, %ds:10
	mov	%cx, %ds:12

# Get hd0 data
# 获取第一个硬盘信息，赋值硬盘参数列表
# 利用中断向量0x41的值，也即是hd0参数列表的地址。
# 第二个硬盘参数表首址是中断向量0x46的值。
# 0x90080存放第一个硬盘表，0x90090存放第二个硬盘表。
# pc机上的中断向量表 : pc机bios在初始化时会在物理内存
# 开始的一页内存中存放中断向量表，每个中断向量表对应的
# 中断服务处理程序isr的地址使用4个字节来表示。但是某些
# 中断向量却使用其他的值，这包括中断向量0x41和0x46，
# 这两个中断向量的处理程序地址实际上就是硬盘参数表的位置。

# 在CPU被加电的时候，最初的1M的内存，是由BIOS为我们安排
# 好的，每一字节都有特殊的用处。

	mov	$0x0000, %ax
	mov	%ax, %ds
	lds	%ds:4*0x41, %si   #取中断向量0x41的值，即hd0参数表地址->ds:si
	mov	$INITSEG, %ax
	mov	%ax, %es
	mov	$0x0080, %di      #传送目的地址：0x9000：0x0080 ->es:di
	mov	$0x10, %cx        #传送16个字节
	rep
	movsb

# Get hd1 data

	mov	$0x0000, %ax
	mov	%ax, %ds
	lds	%ds:4*0x46, %si   #取中断向量0x46的值，即hd0参数表地址->ds:si
	mov	$INITSEG, %ax
	mov	%ax, %es
	mov	$0x0090, %di      #传送目的地址：0x9000：0x0090 ->es:di
	mov	$0x10, %cx        #传送16个字节
	rep
	movsb

# Check that there IS a hd1 :-)
# 检查是否存在第二个硬盘，如果不存在，第二个硬盘表清0.
# 利用bios的int 0x13来取盘类型功能，功能号ah：0x15。
# 0x81是指第二个硬盘

	mov	$0x01500, %ax
	mov	$0x81, %dl
	int	$0x13
	jc	no_disk1
	cmp	$3, %ah
	je	is_disk1
no_disk1:
	mov	$INITSEG, %ax    # 第二个硬盘不存在，则对第二个硬盘表清0
	mov	%ax, %es
	mov	$0x0090, %di
	mov	$0x10, %cx
	mov	$0x00, %ax
	rep
	stosb
is_disk1:

# now we want to move to protected mode ...

	cli			# no interrupts allowed ! 
# 禁止中断

# first we move the system to it's rightful place
# 首先我们将system模块移动到正确的位置。下面程序代码是将system模块移动到0x0000
# 位置，即把从0x10000-0x8ffff的内存数据512k，整体向内存低端移动了0x10000 - 64k

	mov	$0x0000, %ax
	cld			# 'direction'=0, movs moves forward
do_move:
	mov	%ax, %es	# 目的地址为0x000：0x0
	add	$0x1000, %ax
	cmp	$0x9000, %ax  # 移动完成
	jz	end_move
	mov	%ax, %ds	#  源地址 0x1000 : 0x0
	sub	%di, %di
	sub	%si, %si
	mov 	$0x8000, %cx
	rep
	movsw
	jmp	do_move
	
	#将system模块加载到内存的0地址。
	#现在加载中断描述符，lidt指令用于加载中断描述符表idt寄存器。
	#其中加载时只是加载描述符表的线性基地址。中断描述符表中的每一个表项
	#指出发生中断时需要调用的代码信息。lgdt指令用于加载中断描述符表idt。
	#ldgt指令用于加载全局描述符表gdt寄存器。

	#8086处理器的保护模式和实时模式，采用实时模式的寻址，没有虚拟内存空间,
	#首先物理内存的每个位置都是使用20位的地址来标识的。寻址是通过使用cs，ds，ss，es加上段的偏移量。
	 
	#在保护模式下，cpu通过选择子找到段描述符寻址，其中包括全局段表，局部段表，中断表。
	#段选择子通过ldgr寄存器来找到全局段表，通过idtr找到中断表。


end_move:
	#加载中断描述符idt
	mov	$SETUPSEG, %ax	# right, forgot this at first. didn't work :-)
	mov	%ax, %ds
	lidt	idt_48		# load idt with 0,0
	lgdt	gdt_48		# load gdt with whatever appropriate

# that was painless, now we enable A20
# 现在我们使能A20地址线

	#call	empty_8042	# 8042 is the keyboard controller
	#mov	$0xD1, %al	# command write
	#out	%al, $0x64
	#call	empty_8042
	#mov	$0xDF, %al	# A20 on
	#out	%al, $0x60
	#call	empty_8042
	inb     $0x92, %al	# open A20 line(Fast Gate A20).
	orb     $0b00000010, %al
	outb    %al, $0x92

# well, that went ok, I hope. Now we have to reprogram the interrupts :-(
# we put them right after the intel-reserved hardware interrupts, at
# int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
# messed this up with the original PC, and they haven't been able to
# rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
# which is used for the internal hardware interrupts as well. We just
# have to reprogram the 8259's, and it isn't fun.

# 下面的代码是给中断编程，我们将他放在处于intel保留的硬件中断后面，在
# int 0x20 -- 0x2f，在那里它们不会引起中断。
# 下面是8259芯片的简介 : 8259芯片是一种可编程控制芯片。每片可以管理8个中断源。
# 通过多片的级联方式，能构成最多管理64个中断向量的系统。在pc/at系列的兼容机中，
# 使用了两个8259a芯片，共可管理15级中断向量。主8259a芯片的端口基址是0x20，从芯片是0xa0.

# 0x11表示初始化命令开始，是icw1命令字，表示边沿触发，多片8259级联,最后要发送icw4命令字。
# 8259a的编程就是根据应用程序需要将初始化字icw1 -- icw4和操作命令字ocw1 -- ocw3分别写入
# 初始化命令寄存器组和操作命令寄存器组。

# .word 0x00eb,0x00eb来表示跳转值为0的指令，其实还是直接执行下条指令，两条指令可以提供14--20
# 个时钟周期的延迟作用； 0xeb是直接跳转指令操作码，带一个字节的相对地址
# 偏移量。0x00eb表示跳转值是0的一条指令，因此还是直接执行下一条指令。

	mov	$0x11, %al		# initialization sequence(ICW1)
					# ICW4 needed(1),CASCADE mode,Level-triggered
	out	%al, $0x20		# send it to 8259A-1
	.word	0x00eb,0x00eb		# jmp $+2, jmp $+2
	out	%al, $0xA0		# and to 8259A-2
	.word	0x00eb,0x00eb
	mov	$0x20, %al		# start of hardware int's (0x20)(ICW2)
	out	%al, $0x21		# from 0x20-0x27
	.word	0x00eb,0x00eb
	mov	$0x28, %al		# start of hardware int's 2 (0x28)
	out	%al, $0xA1		# from 0x28-0x2F
	.word	0x00eb,0x00eb		#               IR 7654 3210
	mov	$0x04, %al		# 8259-1 is master(0000 0100) --\
	out	%al, $0x21		#				|
	.word	0x00eb,0x00eb		#			 INT	/
	mov	$0x02, %al		# 8259-2 is slave(       010 --> 2)
	out	%al, $0xA1
	.word	0x00eb,0x00eb
	mov	$0x01, %al		# 8086 mode for both
	out	%al, $0x21
	.word	0x00eb,0x00eb
	out	%al, $0xA1
	.word	0x00eb,0x00eb
	mov	$0xFF, %al		# mask off all interrupts for now  屏蔽所有的主芯片的中断请求
	out	%al, $0x21
	.word	0x00eb,0x00eb
	out	%al, $0xA1    # 屏蔽芯片所有的中断请求

# well, that certainly wasn't fun :-(. Hopefully it works, and we don't
# need no steenking BIOS anyway (except for the initial loading :-).
# The BIOS-routine wants lots of unnecessary data, and it's less
# "interesting" anyway. This is how REAL programmers do it.
#
# Well, now's the time to actually move into protected mode. To make
# things as simple as possible, we do no register set-up or anything,
# we let the gnu-compiled 32-bit programs do that. We just jump to
# absolute address 0x00000, in 32-bit protected mode.
	#mov	$0x0001, %ax	# protected mode (PE) bit
	#lmsw	%ax		# This is it!
	mov	%cr0, %eax	# get machine status(cr0|MSW)	加载cr0
	bts	$0, %eax	# turn on the PE-bit 
	mov	%eax, %cr0	# protection enabled   CPU处于保护模式
				
				# segment-descriptor        (INDEX:TI:RPL)
	.equ	sel_cs0, 0x0008 # select for code segment 0 (  001:0 :00) 
	ljmp	$sel_cs0, $0	# jmp offset 0 of code segment 0 in gdt
	
# 跳转到cs段8，偏移量为0。我们已经将system模块移动到0x00000处，所以这里的偏移地址
# 是0.这里的段值的8已经是保护模式下的段选择符了，用于选择描述符表和描述符表项以及
# 所要求的特权级。 段选择符长度为16位；0-1位表示请求的特权级0--3；Linus只只使用了2级:
# 0级系统级和3级用户级。第2位用于选择是全局描述符表还是局部描述符表。3-15位是描述表项
# 的索引，指出是第几项描述符。 8 -- 0000，0000，0000，1000，表示请求的特权级是0--系统级，
# 使用全局描述符表第1项，该代码指出代码的基地址是0，因此这里的跳转指令就回去执行system中的代码。
 

# This routine checks that the keyboard command queue is empty
# No timeout is used - if this hangs there is something wrong with
# the machine, and we probably couldn't proceed anyway.

# 下面的代码检查键盘命令队列是否为空。如果这里死机表示PC有问题。
# 只有当输入缓冲区为空时才可以对其进行写的操作。
empty_8042:
	.word	0x00eb,0x00eb  #延迟操作
	in	$0x64, %al	# 8042 status port
	test	$2, %al		# is input buffer full?
	jnz	empty_8042	# yes - loop
	ret
	
# 数据描述：	
#	(1)Linux的任务： 
# ---定义GDT表 
# ---定义LDT表 
# ---初始化的时候执行LGDT指令，将GDT表的基地址装入到GDTR中 
# ---进程初始化的时候执行LLDT指令，将LLDT表的基地址装入到LDTR中 

# (2)CPU的任务 
# ---用GDTR寄存器保存GDT表的基地址 
# ---用LDTR寄存器保存当前进程的LDT表的基地址 
# ---需要访问内存的时候，利用LDTR(或者GDTR,多数情况下是前者)找到相应的表，再根据提供的内存地址的某些部分
#    找到相应的表项，然后再对表项的内容继续操作，得到最终的物理地址。所有这些操作都是在一条指令的指令周期里面完成的。 

# gdt -- 描述符表的主要作用是将应用程序的逻辑地址转换为线性地址。
# 全局描述表开始，描述发表由多个8字节长的描述符项组成，这里给出3个描述符项：
# 第一项无用，但必须存在。第二项是系统代码段描述符，第三段是系统数据段

gdt:
	.word	0,0,0,0		# dummy 第一个描述符不可用，主要适用于保护
	
# 系统代码段描述符。加载代码段时，使用这个偏移量。段描述符共64位。
# 0 -- 15 limit字段决定段的长度
# 16 -- 39 56 -- 63段的首字节的线性地址
# 40 -- 43 描述段的类型和存取权限。
# 44 系统标志；如果被清0，则是系统端
# 45 -- 46 dpl 描述符的特权级；用于限制这个段的存取。表示为访问
#              这个段而要求的cpu的最小优先级
# 47 -- 1
# 48 -- 51
# 52 被linux忽略
# 53 -- 0
# 54 -- d/s 
# 55 -- g 力度标志

	.word	0x07FF		# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		# base address=0
	.word	0x9A00		# code read/exec
	.word	0x00C0		# granularity=4096, 386
# 从高地址到低地址为 00c0 9a00 0000 07ff
# 偏移量是：07ff,描述符为：07ff

# 系统数据段描述符。当加载数据段寄存器时使用的是这个偏移量。
	.word	0x07FF		# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		# base address=0
	.word	0x9200		# data read/write
	.word	0x00C0		# granularity=4096, 386
	
#加载中断描述符表寄存器idtr的指令lidt要求的6字节操作数，前2字节是IDT表的限长
#后4字节是idt表在线性地址空间中的32位基地址
idt_48:
	.word	0			# idt limit=0
	.word	0,0			# idt base=0L

#加载全局描述符表寄存器gdtr的指令lgdt要求的6字节操作数，前2字节是gdt表的限长，
#后4字节是gdt表的线性地址空间。全局长度设置为 2KB(0x7ff)，因为每8个字节组成一个
#段描述符项，表中可共有256项。4字节线性基地址为 0x0009<<16+0x0200+gdt,即0x90200+gdt。
gdt_48:
	.word	0x800			# gdt limit=2048, 256 GDT entries
	.word   512+gdt, 0x9		# gdt base = 0X9xxxx, 
	# 512+gdt is the real gdt after setup is moved to 0x9020 * 0x10
	
.text
endtext:
.data
enddata:
.bss
endbss:
