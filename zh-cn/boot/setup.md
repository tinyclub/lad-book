	.code16
#
# setup.s ��һ������ϵͳ���س�������ROM BIOS�ж϶�ȡ����ϵͳ���ݣ�
# ��δ����ѯbios�й��ڴ�/����/����������������Щ���ݱ��浽0x90000
# ��ʼ��λ��(��0x90000-0x901FF��Ҳ����ԭ��bootsect����ĵط�)��
# Ȼ��setup����systemģ���0x10000~0x8ffff(512KB)���������ƶ���
#	�ڴ�ľ��Ե�ַ0x00000����Ȼ������ж���������Ĵ���(idtr)��ȫ��
# ��������Ĵ���(gdtr)������A20��ַ�ߣ��������������жϿ���оƬ8259A��
# ��Ӳ���ն˺��������ó�Ϊ0x20~0x2f,�������CPU�Ŀ��ƼĴ���CR0������
# ��32λ����ģʽ���У�����ת��systemģ���head.s����������С�


					--------------------
					-      ������      -
					-------------------- -----	
					-   ���ݶ�������   -   |��ʱȫ����������(gdt) 
					--------------------   |
					-   �����������   -   |
					-------------------- -----
					-   setup.S����    -
					-------------------- 0x90200
					-   ϵͳ����       -
					-------------------- 0x90000
					-     ������       -
					--------------------   --------------
					-    ��ģ��        -          |
					--------------------          |  systemģ�� 
					-   �ڴ����ģ��   -          | 
					--------------------          |
					-    �ں�ģ��      -          |
					--------------------          |
					-    main.c        -          |
					--------------------          |
					-     head.S       -          |
					--------------------          |
					-------------------- 0x00000 -------- 
					
					
	.equ INITSEG, 0x9000	# ԭ��bootsect�����Ķ�
	.equ SYSSEG, 0x1000	# system loaded at 0x10000 (65536).
	.equ SETUPSEG, 0x9020	# ������Ķε�ַ

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

#  ���������̵Ĺ��̶���˳�������ڽ����λ�ñ����Ա�����
#  ��DS���ó�INITSEG(0x9000)
	mov	$INITSEG, %ax	# this is done in bootsect already, but...
	mov	%ax, %ds
# ����ϵͳ�ж�0x10��ȡ���λ�á��������ж�ǰ��׼���͵����ж�
	mov	$0x03, %ah	# read cursor pos
	xor	%bh, %bh
	int	$0x10		# save it in known place, con_init fetches
	mov	%dx, %ds:0	# it from 0x90000. ����Ϣ������0x90000��������̨��ʼ��ʱ����ȡ��
# Get memory size (extended mem, kB)
# ��ȡ��չ�ڴ��С�������ж�0x15�����ܺ�ah��0x88��ͬʱ���õ���չ�ڴ汣�浽0x90002
	mov	$0x88, %ah 
	int	$0x15
	mov	%ax, %ds:2

# Get video-card data:
# �����������ȡ�õ��ǵ�ǰ���Կ�����ʾģʽ�������ж�0x10�����ܺ�ah��0xf��
# 0x90004��ŵ�ǰҳ��0x90006��ʾģʽ��0x90007�ַ�����

	mov	$0x0f, %ah
	int	$0x10
	mov	%bx, %ds:4	# bh = display page
	mov	%ax, %ds:6	# al = video mode, ah = window width

# check for EGA/VGA and some config parameters
# �����ʾģʽ����ȡ�ò���������ega��vga����ʾ��������ģʽ��
# �����ж�0x10��ʵ�ֶ�ȡ��Ϣ�����������Ϣ���档
# 0x9000A����Դ��С��0x9000B��ʾ״̬(��ɫ���ǵ�ɫ)��
# 0x9000C�Կ�����������

	mov	$0x12, %ah
	mov	$0x10, %bl
	int	$0x10
	mov	%ax, %ds:8
	mov	%bx, %ds:10
	mov	%cx, %ds:12

# Get hd0 data
# ��ȡ��һ��Ӳ����Ϣ����ֵӲ�̲����б�
# �����ж�����0x41��ֵ��Ҳ����hd0�����б�ĵ�ַ��
# �ڶ���Ӳ�̲�������ַ���ж�����0x46��ֵ��
# 0x90080��ŵ�һ��Ӳ�̱�0x90090��ŵڶ���Ӳ�̱�
# pc���ϵ��ж������� : pc��bios�ڳ�ʼ��ʱ���������ڴ�
# ��ʼ��һҳ�ڴ��д���ж�������ÿ���ж��������Ӧ��
# �жϷ��������isr�ĵ�ַʹ��4���ֽ�����ʾ������ĳЩ
# �ж�����ȴʹ��������ֵ��������ж�����0x41��0x46��
# �������ж������Ĵ�������ַʵ���Ͼ���Ӳ�̲������λ�á�

# ��CPU���ӵ��ʱ�������1M���ڴ棬����BIOSΪ���ǰ���
# �õģ�ÿһ�ֽڶ���������ô���

	mov	$0x0000, %ax
	mov	%ax, %ds
	lds	%ds:4*0x41, %si   #ȡ�ж�����0x41��ֵ����hd0�������ַ->ds:si
	mov	$INITSEG, %ax
	mov	%ax, %es
	mov	$0x0080, %di      #����Ŀ�ĵ�ַ��0x9000��0x0080 ->es:di
	mov	$0x10, %cx        #����16���ֽ�
	rep
	movsb

# Get hd1 data

	mov	$0x0000, %ax
	mov	%ax, %ds
	lds	%ds:4*0x46, %si   #ȡ�ж�����0x46��ֵ����hd0�������ַ->ds:si
	mov	$INITSEG, %ax
	mov	%ax, %es
	mov	$0x0090, %di      #����Ŀ�ĵ�ַ��0x9000��0x0090 ->es:di
	mov	$0x10, %cx        #����16���ֽ�
	rep
	movsb

# Check that there IS a hd1 :-)
# ����Ƿ���ڵڶ���Ӳ�̣���������ڣ��ڶ���Ӳ�̱���0.
# ����bios��int 0x13��ȡ�����͹��ܣ����ܺ�ah��0x15��
# 0x81��ָ�ڶ���Ӳ��

	mov	$0x01500, %ax
	mov	$0x81, %dl
	int	$0x13
	jc	no_disk1
	cmp	$3, %ah
	je	is_disk1
no_disk1:
	mov	$INITSEG, %ax    # �ڶ���Ӳ�̲����ڣ���Եڶ���Ӳ�̱���0
	mov	%ax, %es
	mov	$0x0090, %di
	mov	$0x10, %cx
	mov	$0x00, %ax
	rep
	stosb
is_disk1:

# now we want to move to protected mode ...

	cli			# no interrupts allowed ! 
# ��ֹ�ж�

# first we move the system to it's rightful place
# �������ǽ�systemģ���ƶ�����ȷ��λ�á������������ǽ�systemģ���ƶ���0x0000
# λ�ã����Ѵ�0x10000-0x8ffff���ڴ�����512k���������ڴ�Ͷ��ƶ���0x10000 - 64k

	mov	$0x0000, %ax
	cld			# 'direction'=0, movs moves forward
do_move:
	mov	%ax, %es	# Ŀ�ĵ�ַΪ0x000��0x0
	add	$0x1000, %ax
	cmp	$0x9000, %ax  # �ƶ����
	jz	end_move
	mov	%ax, %ds	#  Դ��ַ 0x1000 : 0x0
	sub	%di, %di
	sub	%si, %si
	mov 	$0x8000, %cx
	rep
	movsw
	jmp	do_move
	
	#��systemģ����ص��ڴ��0��ַ��
	#���ڼ����ж���������lidtָ�����ڼ����ж���������idt�Ĵ�����
	#���м���ʱֻ�Ǽ���������������Ի���ַ���ж����������е�ÿһ������
	#ָ�������ж�ʱ��Ҫ���õĴ�����Ϣ��lgdtָ�����ڼ����ж���������idt��
	#ldgtָ�����ڼ���ȫ����������gdt�Ĵ�����

	#8086�������ı���ģʽ��ʵʱģʽ������ʵʱģʽ��Ѱַ��û�������ڴ�ռ�,
	#���������ڴ��ÿ��λ�ö���ʹ��20λ�ĵ�ַ����ʶ�ġ�Ѱַ��ͨ��ʹ��cs��ds��ss��es���϶ε�ƫ������
	 
	#�ڱ���ģʽ�£�cpuͨ��ѡ�����ҵ���������Ѱַ�����а���ȫ�ֶα��ֲ��α��жϱ�
	#��ѡ����ͨ��ldgr�Ĵ������ҵ�ȫ�ֶα�ͨ��idtr�ҵ��жϱ�


end_move:
	#�����ж�������idt
	mov	$SETUPSEG, %ax	# right, forgot this at first. didn't work :-)
	mov	%ax, %ds
	lidt	idt_48		# load idt with 0,0
	lgdt	gdt_48		# load gdt with whatever appropriate

# that was painless, now we enable A20
# ��������ʹ��A20��ַ��

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

# ����Ĵ����Ǹ��жϱ�̣����ǽ������ڴ���intel������Ӳ���жϺ��棬��
# int 0x20 -- 0x2f�����������ǲ��������жϡ�
# ������8259оƬ�ļ�� : 8259оƬ��һ�ֿɱ�̿���оƬ��ÿƬ���Թ���8���ж�Դ��
# ͨ����Ƭ�ļ�����ʽ���ܹ���������64���ж�������ϵͳ����pc/atϵ�еļ��ݻ��У�
# ʹ��������8259aоƬ�����ɹ���15���ж���������8259aоƬ�Ķ˿ڻ�ַ��0x20����оƬ��0xa0.

# 0x11��ʾ��ʼ�����ʼ����icw1�����֣���ʾ���ش�������Ƭ8259����,���Ҫ����icw4�����֡�
# 8259a�ı�̾��Ǹ���Ӧ�ó�����Ҫ����ʼ����icw1 -- icw4�Ͳ���������ocw1 -- ocw3�ֱ�д��
# ��ʼ������Ĵ�����Ͳ�������Ĵ����顣

# .word 0x00eb,0x00eb����ʾ��תֵΪ0��ָ���ʵ����ֱ��ִ������ָ�����ָ������ṩ14--20
# ��ʱ�����ڵ��ӳ����ã� 0xeb��ֱ����תָ������룬��һ���ֽڵ���Ե�ַ
# ƫ������0x00eb��ʾ��תֵ��0��һ��ָ���˻���ֱ��ִ����һ��ָ�

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
	mov	$0xFF, %al		# mask off all interrupts for now  �������е���оƬ���ж�����
	out	%al, $0x21
	.word	0x00eb,0x00eb
	out	%al, $0xA1    # ����оƬ���е��ж�����

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
	mov	%cr0, %eax	# get machine status(cr0|MSW)	����cr0
	bts	$0, %eax	# turn on the PE-bit 
	mov	%eax, %cr0	# protection enabled   CPU���ڱ���ģʽ
				
				# segment-descriptor        (INDEX:TI:RPL)
	.equ	sel_cs0, 0x0008 # select for code segment 0 (  001:0 :00) 
	ljmp	$sel_cs0, $0	# jmp offset 0 of code segment 0 in gdt
	
# ��ת��cs��8��ƫ����Ϊ0�������Ѿ���systemģ���ƶ���0x00000�������������ƫ�Ƶ�ַ
# ��0.����Ķ�ֵ��8�Ѿ��Ǳ���ģʽ�µĶ�ѡ����ˣ�����ѡ����������������������Լ�
# ��Ҫ�����Ȩ���� ��ѡ�������Ϊ16λ��0-1λ��ʾ�������Ȩ��0--3��Linusֻֻʹ����2��:
# 0��ϵͳ����3���û�������2λ����ѡ����ȫ�����������Ǿֲ���������3-15λ����������
# ��������ָ���ǵڼ����������� 8 -- 0000��0000��0000��1000����ʾ�������Ȩ����0--ϵͳ����
# ʹ��ȫ�����������1��ô���ָ������Ļ���ַ��0������������תָ��ͻ�ȥִ��system�еĴ��롣
 

# This routine checks that the keyboard command queue is empty
# No timeout is used - if this hangs there is something wrong with
# the machine, and we probably couldn't proceed anyway.

# ����Ĵ����������������Ƿ�Ϊ�ա��������������ʾPC�����⡣
# ֻ�е����뻺����Ϊ��ʱ�ſ��Զ������д�Ĳ�����
empty_8042:
	.word	0x00eb,0x00eb  #�ӳٲ���
	in	$0x64, %al	# 8042 status port
	test	$2, %al		# is input buffer full?
	jnz	empty_8042	# yes - loop
	ret
	
# ����������	
#	(1)Linux������ 
# ---����GDT�� 
# ---����LDT�� 
# ---��ʼ����ʱ��ִ��LGDTָ���GDT��Ļ���ַװ�뵽GDTR�� 
# ---���̳�ʼ����ʱ��ִ��LLDTָ���LLDT��Ļ���ַװ�뵽LDTR�� 

# (2)CPU������ 
# ---��GDTR�Ĵ�������GDT��Ļ���ַ 
# ---��LDTR�Ĵ������浱ǰ���̵�LDT��Ļ���ַ 
# ---��Ҫ�����ڴ��ʱ������LDTR(����GDTR,�����������ǰ��)�ҵ���Ӧ�ı��ٸ����ṩ���ڴ��ַ��ĳЩ����
#    �ҵ���Ӧ�ı��Ȼ���ٶԱ�������ݼ����������õ����յ������ַ��������Щ����������һ��ָ���ָ������������ɵġ� 

# gdt -- �����������Ҫ�����ǽ�Ӧ�ó�����߼���ַת��Ϊ���Ե�ַ��
# ȫ��������ʼ�����������ɶ��8�ֽڳ�������������ɣ��������3���������
# ��һ�����ã���������ڡ��ڶ�����ϵͳ���������������������ϵͳ���ݶ�

gdt:
	.word	0,0,0,0		# dummy ��һ�������������ã���Ҫ�����ڱ���
	
# ϵͳ����������������ش����ʱ��ʹ�����ƫ����������������64λ��
# 0 -- 15 limit�ֶξ����εĳ���
# 16 -- 39 56 -- 63�ε����ֽڵ����Ե�ַ
# 40 -- 43 �����ε����ͺʹ�ȡȨ�ޡ�
# 44 ϵͳ��־���������0������ϵͳ��
# 45 -- 46 dpl ����������Ȩ����������������εĴ�ȡ����ʾΪ����
#              ����ζ�Ҫ���cpu����С���ȼ�
# 47 -- 1
# 48 -- 51
# 52 ��linux����
# 53 -- 0
# 54 -- d/s 
# 55 -- g ���ȱ�־

	.word	0x07FF		# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		# base address=0
	.word	0x9A00		# code read/exec
	.word	0x00C0		# granularity=4096, 386
# �Ӹߵ�ַ���͵�ַΪ 00c0 9a00 0000 07ff
# ƫ�����ǣ�07ff,������Ϊ��07ff

# ϵͳ���ݶ������������������ݶμĴ���ʱʹ�õ������ƫ������
	.word	0x07FF		# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		# base address=0
	.word	0x9200		# data read/write
	.word	0x00C0		# granularity=4096, 386
	
#�����ж���������Ĵ���idtr��ָ��lidtҪ���6�ֽڲ�������ǰ2�ֽ���IDT����޳�
#��4�ֽ���idt�������Ե�ַ�ռ��е�32λ����ַ
idt_48:
	.word	0			# idt limit=0
	.word	0,0			# idt base=0L

#����ȫ����������Ĵ���gdtr��ָ��lgdtҪ���6�ֽڲ�������ǰ2�ֽ���gdt����޳���
#��4�ֽ���gdt������Ե�ַ�ռ䡣ȫ�ֳ�������Ϊ 2KB(0x7ff)����Ϊÿ8���ֽ����һ��
#������������пɹ���256�4�ֽ����Ի���ַΪ 0x0009<<16+0x0200+gdt,��0x90200+gdt��
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
