
# bootsect.s 程序

## 1. Linux0.11内核启动过程概述
1. 当PC的电源打开后，80x86结构的CPU将进入实模式，并从地址0XFFFF0开始自动执行。
2. PC机的BIOS将执行某些系统的检测，并在物理地址0处开始初始化中断向量。
3. 启动设备（软驱或硬盘）的第一个扇区（磁盘引导扇区，512字节）读入到内存的绝对地址0x7C00处，并跳转到这个地方运行。

bootsect.s 是磁盘引导块程序，驻留在磁盘的第一个扇区中（引导扇区，0磁道，0磁头，第一个扇区）。自然 bootsect.s 就是在内存中首先运行的程序。


## 1.1 bootsect.s 程序分析

下面主要按照 bootsect.s 实现的功能来分块分析。

### 1.1.1 bootsect.s文件读入内存

```
45 entry start      ! 告知链接程序，程序从start 标号开始执行。
46  start:
47  mov ax,#BOOTSEG  ! ax = 0x07c0；
48  mov ds,ax        ! 将 ds 段寄存器置为0x7C0；
49  mov ax,#INITSEG  ! ax = 0x9000；
50  mov es,ax        ! 将 es 段寄存器置为0x9000；
51  mov cx,#256      ! 移动计数值=256字；
52  sub si,si        ! si=si-si，即si清零，源地址 ds:si = 0x07C0:0x0000
53  sub di,di        ! di清零，目的地址 es:di = 0x9000:0x0000
54  rep              ! 重复前缀rep，相当于loop指令，常和MOVSB配合使用，
                     ! (ES:DI)<-(DS:SI),(si)<-(si)+1,(DI)<-(DI)+1,(cx)<-(cx)-1
                     ! cx不等于0时重复执行，直到cx=0时退出循环
55  movw             !每次移动1个字；
56  jmpi go,INITSEG  ! 间接跳转。ip指针为go标号的地址(段内偏移地址)，cs=INITSEG=0x9000，
                    ! 这里 INITSEG 指跳转到的段地址。
```
此部分主要实现的功能是将bootsect代码所在的内存0x7c00处，移动到内存0x90000处，每次移动1个字，循环搬移256次，即bootsect代码从内存0x7c00处512字节代码拷贝到内存0x90000处。

56行代码也是这里的关键，将代码段寄存器cs(用于存放当前执行程序的段地址)更新为0x90000，IP指令指针指向内存0x90000+段内偏移地址，此后代码将从内存ip所指向的地址开始执行。

说明：内存物理地址 = 段地址 << 4 + 偏移地址 如源地址 ds:si = 0x07C0:0x0005 即内存物理地址为0x7c05。

bootsect.s文件读入内存示图如下：
![image](/zh-cn/images/boot/bootsect_move.png)

### ds、es、ss段和堆栈指针sp设置

```
57 go:  mov ax,cs   ! 将ds、es 和 ss 都置成移动后代码所在的段处(0x9000)。
58      mov ds,ax
59      mov es,ax
60  ! put stack at 0x9ff00.
61      mov ss,ax   !由于程序中有堆栈操作(push,pop,call)，因此必须设置堆栈
62      mov sp,#0xFF00 ! arbitrary value >>512
```
此部分代码功能为设置ds、es和ss段地址(0x9000)，将堆栈指针sp 指向0x9ff00(即0x9000:0xff00)处。由于代码段移动过了，所以要重新设置堆栈段的位置。sp 只要指向远大于512 偏移（即地址0x90200）处都可以。因为从0x90200 地址开始处还要放置setup 程序，而此时setup 程序大约为4 个扇区，因此sp 要指向大于（0x200 + 0x200 * 4 + 堆栈大小）处。

### 1.1.2 将 setup 程序从磁盘读入内存及获取磁盘驱动器参数

磁盘平面图

![image](/zh-cn/images/boot/disk.png)

启动文件在磁盘中位置示意图

![image](/zh-cn/images/boot/disk2.png)


```
! INT 0x13 的使用方法如下：
! 读扇区：
! ah = 0x02 读磁盘扇区到内存；al = 需要读出的扇区数量
! ch = 磁道(柱面)号的低8 位； cl = 开始扇区(0-5 位)，磁道号高2 位(6-7)
！dh = 磁头号； dl = 驱动器号（如果是硬盘则要置位7）
！es:bx 获取到磁盘数据所存放的数据缓冲区； 如果出错则CF 标志置位。
67 load_setup:
68     mov dx,#0x0000   ! 驱动器号0，磁头号0
69     mov cx,#0x0002   ! 开始扇区为2, 磁道号0
70     mov bx,#0x0200   ! es:bx=0x9000:0x200 读取磁盘内容存放地址
71     mov ax,#0x0200+SETUPLEN ! ah=0x02(读磁盘扇区到内存)，al=4(需要读出的扇区个数)
72     int 0x13         ! 产生中断读取磁盘数据
73     jnc ok_load_setup ! CF=0，ok，跳转到ok_load_setup
74     mov dx,#0x0000    ! 失败，对磁盘0进行读操作
75     mov ax,#0x0000 	 ! 复位磁盘
76     int 0x13
77     j load_setup      ! 跳转到load_setup重试
78
79 ok_load_setup:
80
81  ! Get disk drive parameters, specifically nr of sectors/track
    ! 取磁盘驱动器的参数，特别是每道的扇区数量。
    ! 取磁盘驱动器参数 INT 0x13 调用格式和返回信息如下：
    ! ah = 0x08 dl = 驱动器号（如果是硬盘则要置位7 为1）。
    ! 返回信息：
    ! 如果出错则CF 置位，并且ah = 状态码。
    ! ah = 0， al = 0， bl = 驱动器类型（AT/PS2）
    ! ch = 最大磁道号的低8 位，cl = 每磁道最大扇区数(位0-5)，最大磁道号高2 位(位6-7)
    ! dh = 最大磁头数， dl = 驱动器数量，
    ! es:di 软驱磁盘参数表。
82
83     mov dl,#0x00         ! dl清零
84     mov ax,#0x0800		! AH=8 is get drive parameters
85     int 0x13
86     mov ch,#0x00
87     seg cs               ! 表示下一条语句操作数在cs段寄存器所指的段中
88     mov sectors,cx       ! 软盘最大磁道号不超过256，ch已经足够表示它，
                            ! 因此cl位6-7肯定为0，ch=0，sectors=cx即为每磁道扇区数
89     mov ax,#INITSEG
90     mov es,ax            ! 恢复es的值，因为取磁盘参数改掉了es的值
```

此部分的功能为
- 利用 BIOS 中断 INT 0x13 将 setup 模块从磁盘第2个扇区开始读到0x90200地址(es:bx=0x9000:0x200)开始处，共读4 个扇区。如果读出错，则复位驱动器，并重试，没有退路。
- 利用 BIOS 中断 INT 0x13 取磁盘驱动器的参数，特别是每道的扇区数量，保存在变量sectors。

setup读入内存示意图
![image](/zh-cn/images/boot/load_setup.png)

### 1.1.3 打印信息

代码分析

```
! Print some inane message
! 在显示一些信息('Loading system ...'回车换行，共24 个字符)。
! BIOS中断0x10功能号 ah = 0x03,读光标
! BIOS中断0x10功能号 ah=0x13，显示字符

94     mov ah,#0x03 ! read cursor pos
95     xor bh,bh        ! bh清零，读光标位置。
96     int 0x10
97
98     mov cx,#24 		 ! 共24 个字符。
99     mov bx,#0x0007	 ! page 0, attribute 7 (normal)
100    mov bp,#msg1 	 ! 指向要显示的字符串。
101    mov ax,#0x1301 	 ! write string, move cursor
102    int 0x10 		 ! 写字符串并移动光标。
```

```
244 msg1:
245    .byte 13,10 		! 回车、换行的ASCII 码。
246    .ascii "Loading system ..."
247    .byte 13,10,13,10 	! 共24 个ASCII 码字符。
```

### 1.1.4 SYSTEM模块读入内存

```
104 ! ok, we've written the message, now
105 ! we want to load the system (at 0x10000)
    ! 现在开始将system 模块加载到0x10000(64k)处。
106
107 	mov	ax,#SYSSEG  ! SYSSIZE = 0x3000 指编译连接后system 模块的大小，ax = 0x3000
108 	mov	es,ax		! segment of 0x010000 es = 存放system 的段地址
109 	call	read_it ! 读磁盘上system 模块，es 为输入参数。
120 	call	kill_motor  !关闭驱动器马达，这样就可以知道驱动器的状态了
121
```
#### read_it(待分析)
示图
![image](/zh-cn/images/boot/read_it.png)

#### kill_motor(关闭软驱的马达)

```
233 kill_motor:
234 	push dx ! dx 压栈保护
235 	mov dx,#0x3f2   ! 软驱控制卡的驱动端口，只写。
236 	mov al,#0       ! A 驱动器，关闭FDC，禁止DMA 和中断请求，关闭马达。
237 	outb    ! 将al 中的内容输出到dx 指定的端口去。
238 	pop dx !出栈还原dx的值
239 	ret ! 子程序返回指令，用于段内子程序的返回，完成IP出栈，即(IP)<-(SP)
```
这个子程序用于关闭软驱的马达，这样我们进入内核后它处于已知状态，以后也就无须担心它了。

### 1.1.5 确定使用哪个根文件系统设备

#### linux 0.11 硬盘设备号

Linux 老式的硬盘命名方式,具体值的含义如下：

设备号=主设备号*256 + 次设备号（即dev_no = (major<<8) + minor ）
主设备号：1-内存,2-磁盘,3-硬盘,4-ttyx,5-tty,6-并行口,7-非命名管道

由于1个硬盘中可以有1-4个分区，因此硬盘还依据分区的不同，用次设备号进行指定分区。两个硬盘的所有逻辑设备号如下表。


逻辑设备号 | 对应设备文件 | 说明
---|---|---
0x300 | /dev/hd0 | 代表整个第1个硬盘
0x301 | /dev/hd1 | 第1个盘的第1个分区
0x304 | /dev/hd4 | 第1个盘的第4个分区
0x305 | /dev/hd5 | 代表整个第2个硬盘
0x306 | /dev/hd6 | 第2个盘的第1个分区
0x309 | /dev/hd9 | 第2个盘的第4个分区

#### linux 0.11 磁盘设备号

在Linux中软驱的主设备号是2，次设备号 = type*4 + nr，其中
nr 为0-3 分别对应软驱A、B、C 或D；type 是软驱的类型（2->1.2M 或7->1.44M 等）。

逻辑设备号 | 对应设备文件 | 说明
---|---|---
0x0208 | /dev/PS0 (2,28) | 1.44MB A驱动器
0x021c | /dev/at0 (2,8) | 1.2MB A驱动器

代码分析
```
117 	seg cs
118 	mov	ax,root_dev
119 	cmp	ax,#0   !判断root_dev是否为0
120 	jne	root_defined    ! 不等于0，即被定义，跳转到root_define标号处
        ! sectors:保存着每磁道扇区数
        ! sectors = 15 : 说明是1.2MB的驱动器
        ! sectors = 18 : 说明是1.44M软驱
121 	seg cs
122 	mov	bx,sectors
123 	mov	ax,#0x0208		! /dev/ps0 - 1.2Mb
124 	cmp	bx,#15          ! 判断每磁道扇区数是否=15
125 	je	root_defined    ! 如果等于，则ax 中就是引导驱动器的设备号
126 	mov	ax,#0x021c		! /dev/PS0 - 1.44Mb
127 	cmp	bx,#18
128 	je	root_defined
129 undef_root:             ! 如果都不一样，则死循环（死机）
130 	jmp undef_root
131 root_defined:
132 	seg cs
133 	mov	root_dev,ax     ! 将检查过的设备号保存起来
...
...
249 .org 508    ! 段的偏移值，表示root_dev两个字节的数据存放在段偏移508(0x9000:0x1fc)处
250 root_dev:
251 	.word ROOT_DEV  !ROOT_DEV = 0x306 指定根文件系统设备是第2个硬盘的第1个分区
```
此部分实现功能为检查要使用哪个根文件系统设备（简称根设备）。如果已经指定了设备(root_dev!=0)就直接使用给定的设备。否则就需要根据BIOS 报告的每磁道扇区数来确定到底使用/dev/PS0 (2,28) 还是 /dev/at0 (2,8)。代码中可看到root_dev默认设置为0x0306，主要是因为当时linus开发linux系统时是在第2个硬盘第一个分区。这个值可根据你自己的根文件系统所在硬盘和分区进行修改。也可在Makefile文件中另行指定你自己的值，编译内核时，内核Image的创建程序tools/build会使用你指定的值来设置你的根文件系统所在设备号。


#### 内存地址偏移如图所示

![image](/zh-cn/images/boot/memory_addr_offset.png)


### 1.1.6 跳转执行setup

```
135 ! after that (everyting loaded), we jump to
136 ! the setup-routine loaded directly after
137 ! the bootblock:
    ! 到此，所有程序都加载完毕，我们就跳转到被
    ! 加载在bootsect 后面的setup 程序去。
138
139    jmpi 0,SETUPSEG ! 跳转到0x9020:0000(setup.s 程序的开始处)。
```

## 1.2 总结

