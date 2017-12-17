#Linux0.11内核启动过程#

# I、Linux0.11内核启动过程概述：#
1. 当PC的电源打开后，80x86结构的CPU将进入实模式，并从地址0XFFFF0开始自动执行。
2. PC机的BIOS将执行某些系统的检测，并在物理地址0处开始初始化中断向量。
3. 启动设备（软驱或硬盘）的第一个扇区（磁盘引导扇区，512字节）读入到内存的绝对地址0x7C00处，并跳转到这个地方运行。

## Linux0.11启动代码目录boot下文件介绍： ##

在boot目录下主要有bootsect.s,head.s,setup.s三个汇编文件，三个汇编文件完成了启动引导的流程，过程图如下图所示：
![](https://i.imgur.com/i60Pf71.png)

**1、bootsect.s程序：**

bootsec.s是磁盘引导块程序，驻留在磁盘的第一个扇区中（引导扇区，0磁道，0磁头，第一个扇区）。

**2、setup.s程序**

setup.s是一个操作系统加载程序，它的主要作用是利用ROM BIOS中断读取机器系统数据，并将这些数据保存到0x90000开始的位置。

**3、head.s程序**

从这里开始，内核完全都是在保护模式下运行了。

#II、 boot/bootsect.s启动内核时在内存中的位置和移动情况:#

1. 8086体系结构的计算机在上电后将由BIOS进行系统的自检。
2. 之后BIOS会将bootsect.s文件读入内存的0x7C00（31k）处。
3. 然后跳转到此执行引导扇区的代码。
4. 这段代码执行时会将自己移动的内存的0x90000（576k）到0xA0000处一共64K，并把存储设备中的setup.s文件读入到内存的0x90200（576.5k）处，system模块读入到内存的0x10000（64k）处。启动引导时内核在内存中的位置和移动后的位置情况如下图所示：

![](https://i.imgur.com/rlb8xdh.png)


----------

# III 、bootsect.s程序分析 #

**目录：**


1. bootsect.s文件读入内存 
2. setup读入内存及读取磁盘驱动器参数
3. 打印信息代码分析
4. SYSTEM模块读入内存 
5. 确定使用哪个根文件系统设备
6. 跳转执行setup


# 1、bootsect.s文件读入内存 #

**1.1、代码分析：**

	entry start 	! 告知连接程序，程序从start 标号开始执行。
	start:		    ! 47--56 行作用是将自身(bootsect)从目前段位置0x07c0(31k)
    mov ax,#BOOTSEG ! 将ds 段寄存器置为0x7C0；
    mov ds,ax
    mov ax,#INITSEG ! 将es 段寄存器置为0x9000；
    mov es,ax
    mov cx,#256 	! 移动计数值=256 字；
    sub si,si 		! 源地址 ds:si = 0x07C0:0x0000
    sub di,di 		! 目的地址 es:di = 0x9000:0x0000
    rep 			! 重复执行，直到cx = 0
    movw		    ! 移动1 个字；
    jmpi go,INITSEG ! 间接跳转。这里INITSEG 指出跳转到的段地址。

**1.2、bootsect.s文件读入内存示图**



![](https://i.imgur.com/NFk3m3Y.png)

**1.3、ds,es和ss端处设置**

    go: mov ax,cs ! 将ds、es 和ss 都置成移动后代码所在的段处(0x9000)。
    mov ds,ax 	    ！由于程序中有堆栈操作(push,pop,call)，因此必须设置堆栈。
    mov es,ax

##

**1.4、移动堆栈指针程序分析**

- ! put stack at 0x9ff00. ! 将堆栈指针sp 指向0x9ff00(即0x9000:0xff00)处
- ! 由于代码段移动过了，所以要重新设置堆栈段的位置。
- ! sp 只要指向远大于512 偏移（即地址0x90200）处
- ! 都可以。因为从0x90200 地址开始处还要放置setup 程序，
- ! 而此时setup 程序大约为4 个扇区，因此sp 要指向大
- ! 于（0x200 + 0x200 * 4 + 堆栈大小）处。

##

    mov ss,ax
    mov sp,#0xFF00 ! arbitrary value >>512

##
# 2、setup读入内存及读取磁盘驱动器参数 #

**2.1、磁盘平面图：**

![](https://i.imgur.com/HdvdP5q.png)


**2.2、启动文件在磁盘中位置示意图：**

![](https://i.imgur.com/bNTuQlZ.png)

**2.3、setup读入内存示意图：**
![](https://i.imgur.com/nQ8nT9y.png)  

**2.4、setup读入内存代码分析**

- ! 用途是利用BIOS 中断INT 0x13 将setup 模块从磁盘第2 个扇区
- ! 开始读到0x90200 开始处，共读4 个扇区。如果读出错，则复位驱动器，并
- ! 重试，没有退路。INT 0x13 的使用方法如下：
- ! 读扇区：
- ! ah = 0x02 读磁盘扇区到内存；al = 需要读出的扇区数量；
- ! ch = 磁道(柱面)号的低8 位； cl = 开始扇区(0-5 位)，磁道号高2 位(6-7)；
- ! dh = 磁头号； dl = 驱动器号（如果是硬盘则要置位7）；
- ! es:bx ??指向数据缓冲区； 如果出错则CF 标志置位。


##

    mov dx,#0x0000 ! drive 0, head 0
    mov cx,#0x0002 ! sector 2, track 0
    mov bx,#0x0200 ! address = 512, in INITSEG
    mov ax,#0x0200+SETUPLEN ! service 2 , 读4个扇区
    int 0x13 ! read it
    jnc ok_load_setup ! ok - continue
    mov dx,#0x0000
    mov ax,#0x0000 	  ! reset the diskette
    int 0x13
    j load_setup


**2.5、setup读入参数代码分析**
##

- ! Get disk drive parameters, specifically nr of sectors/track
- ! 取磁盘驱动器的参数，特别是每道的扇区数量。
- ! 取磁盘驱动器参数INT 0x13 调用格式和返回信息如下：
- ! ah = 0x08 dl = 驱动器号（如果是硬盘则要置位7 为1）。
- ! 返回信息：
- ! 如果出错则CF 置位，并且ah = 状态码。
- ! ah = 0， al = 0， bl = 驱动器类型（AT/PS2）
- ! ch = 最大磁道号的低8 位，cl = 每磁道最大扇区数(位0-5)，最大磁道号高2 位(位6-7)
- ! dh = 最大磁头数， dl = 驱动器数量，
- ! es:di -?? 软驱磁盘参数表。

##

    ok_load_setup:
    mov dl,#0x00
    mov ax,#0x0800 ! AH=8 is get drive parameters
    int 0x13
    mov ch,#0x00
    seg cs ! 表示下一条语句的操作数在cs 段寄存器所指的段中。
    mov sectors,cx ! 保存每磁道扇区数。
    mov ax,#INITSEG
    mov es,ax ! 因为上面取磁盘参数中断改掉了es 的值，这里重新改回。

## 3、打印信息代码分析： ##

- ! Print some inane message
- ! 在显示一些信息('Loading system ...'回车换行，共24 个字符)。
- ! BIOS中断0x10功能号 ah = 0x03,读光标
- ！BIOS中断0x10功能号 ah=0x13，显示字符

##

    mov ah,#0x03 ! read cursor pos
    xor bh,bh	 ! 读光标位置。
    int 0x10
    
    mov cx,#24 		 ! 共24 个字符。
    mov bx,#0x0007	 ! page 0, attribute 7 (normal)
    mov bp,#msg1 	 ! 指向要显示的字符串。
    mov ax,#0x1301 	 ! write string, move cursor
    int 0x10 		 ! 写字符串并移动光标。


##

**msg1：**

    .byte 13,10 		! 回车、换行的ASCII 码。
    .ascii "Loading system ..."
    .byte 13,10,13,10 	! 共24 个ASCII 码字符。
    
    .org 508 			! 表示下面语句从地址508(0x1FC)开始，所以root_dev
   					    ! 在启动扇区的第508 开始的2 个字节中。
    root_dev:
    .word ROOT_DEV 		! 这里存放根文件系统所在的设备号(init/main.c 中会用)。
    boot_flag:
    .word 0xAA55 		! 硬盘有效标识。


----------

# 4、SYSTEM模块读入内存 #

**4.1示图**
![](https://i.imgur.com/IodqOk2.png)


**4.2 代码分析**

- ! ok, we've written the message, now
- ! we want to load the system (at 0x10000) ! 现在开始将system 模块加载到0x10000(64k)处。


----------

    SYSSIZE = 0x3000 ! 指编译连接后system 模块的大小。参见列表1.2 中第92 的说明。
    ! setup 程序从这里开始；
    SYSSEG = 0x1000 ! system loaded at 0x10000 (65536).
    ! system 模块加载到0x10000（64 kB）处；
    ENDSEG = SYSSEG + SYSSIZE ! where to stop loading
		
	！--------------------------------------------------

    mov ax,#SYSSEG
    mov es,ax ! segment of 0x010000 ! es = 存放system 的段地址。
    call read_it ! 读磁盘上system 模块，es 为输入参数。
    call kill_motor ! 关闭驱动器马达，这样就可以知道驱动器的状态了。


**4.3、read_it**
//待分析


**4.4、关闭软驱的马达**

- ! 这个子程序用于关闭软驱的马达，这样我们进入内核后它处于已知状态，以后也就无须担心它了。
##
    kill_motor:
    push dx
    mov dx,#0x3f2 ! 软驱控制卡的驱动端口，只写。
    mov al,#0 ! A 驱动器，关闭FDC，禁止DMA 和中断请求，关闭马达。
    outb ! 将al 中的内容输出到dx 指定的端口去。
    pop dx
    ret

##

# 5、确定使用哪个根文件系统设备 #

##
**5.1、设备号介绍**

- ! ROOT_DEV: 0x000 same type of floppy as boot.
- ! 根文件系统设备使用与引导时同样的软驱设备；
- ! 0x301 first partition on first drive etc
- ! 根文件系统设备在第一个硬盘的第一个分区上，等等；
- ROOT_DEV = 0x306 ! 指定根文件系统设备是第2 个硬盘的第1 个分区。这是Linux 老式的硬盘命名
- ! 方式,具体值的含义如下：
- ! 设备号=主设备号*256 + 次设备号（也即dev_no = (major<<8) + minor ）
- ! （主设备号：1-内存,2-磁盘,3-硬盘,4-ttyx,5-tty,6-并行口,7-非命名管道）
- ! 0x300 /dev/hd0 代表整个第1 个硬盘；
- ! 0x301 /dev/hd1 第1 个盘的第1 个分区；
- ! …
- ! 0x304 /dev/hd4 第1 个盘的第4 个分区；
- ! 0x305 /dev/hd5 代表整个第2 个硬盘盘；
- ! 0x306 /dev/hd6 第2 个盘的第1 个分区；
- ! …
- ! 0x309 /dev/hd9 第2 个盘的第4 个分区；
- ! 从linux 内核0.95 版后已经使用与现在相同的命名方法了。
##

**5.2、内存地址偏移代码：**

    .org 508 ! 表示下面语句从地址508(0x1FC)开始，所以root_dev
    ! 在启动扇区的第508 开始的2 个字节中。
    root_dev:
    .word ROOT_DEV ! 这里存放根文件系统所在的设备号(init/main.c 中会用)。
    boot_flag:
    .word 0xAA55 ! 硬盘有效标识。

##

**5.3、内存地址偏移如图所示：**

![](https://i.imgur.com/etid011.png)
**5.4 代码分析**

- ! After that we check which root-device to use. If the device is
- ! defined (!= 0), nothing is done and the given device is used.
- ! Otherwise, either /dev/PS0 (,28) or /dev/at0 (2,8), depending
- ! on the number of sectors that the BIOS reports currently.
- ! 此后，我们检查要使用哪个根文件系统设备（简称根设备）。如果已经指定了设备(!=0)
- ! 就直接使用给定的设备。否则就需要根据BIOS 报告的每磁道扇区数来
- ! 确定到底使用/dev/PS0 (2,28) 还是 /dev/at0 (2,8)。
- ! 上面一行中两个设备文件的含义：
- ! 在Linux 中软驱的主设备号是2(参见第43 行的注释)，次设备号 = type*4 + nr，其中
- ! nr 为0-3 分别对应软驱A、B、C 或D；type 是软驱的类型（2??1.2M 或7??1.44M 等）。
- ! 因为7*4 + 0 = 28，所以 /dev/PS0 (2,28)指的是1.44M A 驱动器,其设备号是0x021c
- ! 同理 /dev/at0 (2,8)指的是1.2M A 驱动器，其设备号是0x0208。

##
    seg cs
    mov ax,root_dev ! 将根设备号
    cmp ax,#0
    jne root_defined
    seg cs
    mov bx,sectors ! 取上面第88 行保存的每磁道扇区数。如果sectors=15
##
- ! 则说明是1.2Mb 的驱动器；如果sectors=18，则说明是
- ! 1.44Mb 软驱。因为是可引导的驱动器，所以肯定是A 驱。
##
    mov ax,#0x0208 ! /dev/ps0 - 1.2Mb
    cmp bx,#15 ! 判断每磁道扇区数是否=15
    je root_defined ! 如果等于，则ax 中就是引导驱动器的设备号。
    mov ax,#0x021c ! /dev/PS0 - 1.44Mb
    cmp bx,#18
    je root_defined
    undef_root: ! 如果都不一样，则死循环（死机）。
    jmp undef_root
    root_defined:
    seg cs
    mov root_dev,ax ! 将检查过的设备号保存起来。
##

# 6、跳转执行setup #

- ! after that (everyting loaded), we jump to
- ! the setup-routine loaded directly after
- ! the bootblock:
- ! 到此，所有程序都加载完毕，我们就跳转到被
- ! 加载在bootsect 后面的setup 程序去。
##


    jmpi 0,SETUPSEG ! 跳转到0x9020:0000(setup.s 程序的开始处)。

##