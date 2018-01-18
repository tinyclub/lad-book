# 文件系统的初始化
## 概述

本文主要介绍，linux kernel 0.11系统中minix1.0版本文件系统的初始化。主要参考的代码是， [mkfs.minix代码](https://www.kernel.org/pub/linux/utils/util-linux/v2.30/util-linux-2.30.1.tar.gz) 。首先会先描述一下出完成后初始化的数据结构是什么样子的，然后通过实验来看一个新初始化系统的数据组成情况。

## mini1.0文件系统的布局：

| 引导块 | 超级快 | inode位图 | 逻辑块位图 | inode块 | 数据块 |
| ---|---|---|---|---|---|---

  文件系统初始化的过程就是，初始化这个布局的过程。根据mkfs.minix命令参数来初始化超级快，inode的位图，逻辑块位图，以及逻辑块。另外mini1.0文件系统中，将磁盘按照1KB的大小进行划分，也就是最小粒度是1KB。
  
 - 超级块在硬盘中存储的初始化信息，下面列出了超级快的结构体，后面的注释来说明初始化的数值。

```

# 超级快结构体

//include/linux/fs.h
//struct super_block
unsigned short s_ninodes; //inode数 
unsigned short s_nzones;  //总逻辑块数 
unsigned short s_imap_blocks;//i节点位图磁盘块数
unsigned short s_zmap_blocks;//逻辑块位图磁盘块数
unsigned short s_firstdatazone;//数据区开始的第一个逻辑块号
	                
unsigned short s_log_zone_size;//每个逻辑块表示的磁盘块数[以2为底的对数]
unsigned long s_max_size;//以字节表示的最大文件长度
unsigned short s_magic; //文件系统魔术字

```               

 - 对超级块字段一一说明：
1. s_ninodes:用来表示文件系统一共支持多少个inode节点，inode节点可以用户设置，也可以根据系统大小在mkfs来计算，但是最大不能超过65535个，这个字段初始值是:min(65535,用户设置，((is_nzones/3 + MINIX_INODES_PER_BLOCK - 1) & ~(MINIX_INODES_PER_BLOCK - 1)))，此时MINIX_INODES_PER_BLOCK仅仅包含inode在磁盘中存储的部分。
2. s_nzones:用来表示总逻辑块数，他的初始值是磁盘大小除以1024。
3. s_imap_blocks:用来表示需要使用的i节点位图个数。位图初始化状态：第一个字节的第0位为1(这个bit不用，也就是从第1位开始为第一个有效inode)，末尾位图中多余位数为1，中间的为0，UPPER(s_ninodes + 1, BITS_PER_BLOCK)，因为位图的第0位不使用但是要占用1个位所以加1。
4. s_zmap_blocks:逻辑块位图磁盘块数。位图初始化状态：第一个字节的第0位为1,实际的块从第1位开[这个位表示s_firstdatazone指向的块]始，这样初始化的后第0位为1,末尾位图中多余的bit位为1。UPPER(s_nzones - (1+s_imap_blocks+INODE_BLOCKS), BITS_PER_BLOCK+1),计算了除了第一个块，inode位图块和inode块，剩下所有块需要用的位图个数。[为什么没有减去超级块占用的逻辑块？，我理解，因为位图第0位是不使用的，所以需要表示的磁盘块个数是，s_nzones-(1个引导块+1个超级快+s_imap_blocks+INODE_BLOCKS)+1个不用块位图位置，这里相当于是抵消了1]。
5. s_firstdatazone:数据区开始的第一个逻辑块号，第一个逻辑块是0号。初始化为:(2+s_imap_blocks+s_zmap_blocks+INODE_BLOCKS)
6. s_log_zone_size:每个逻辑块表示的磁盘块数[以2为底的对数]，minix1.0中，逻辑块大小就是磁盘块大小，都是1KB。
7. s_max_size:以字节表示的最大文件长度，初始化为:(7+512+512*512)*1024=268966912，inode中7个直接块，1个间接块，1个二次间接块。
8. s_magic:minix1.0文件系统魔术字，初始化为0x137f。
 - inode在硬盘中存储的初始化信息，在系统初始化的时候至少会初始化一个inode，来表示最顶层的目录，下面列出了inode的结构体，后面的注释来说明初始化的数值。

```

## inode 结构体

//include/linux/fs.h
//struct m_inode
unsigned short i_mode; //文件类型和属性(rwx位)
unsigned short i_uid;  //文件宿主的用户id
unsigned long i_size;  //文件长度
unsigned char i_gid;  //文件宿主组id
unsigned char i_nlinks; //连接数
unsigned short i_zone[9]; //文件所占用磁盘上逻辑块号数组；zone[0]~zone[6]直接逻辑块号 zone[7]一次间接块号 zone[8]二次间接块号 如果是设备文件则zone[0]指的是设备号
/** 初始化为：在没有坏块的情况下,i_zone[0]=s_firstdatazone
	这第一个块中的内容是：初始化了两个目录项，'.'和'..''目录项结构体如下：
	struct dir_entry {
	unsigned short inode;
	char name[NAME_LEN];
    };共16个字节，这第一个逻辑块最开始内容全部是'\0',然后0-15个字节被修改为inode为1,name是'.'
    第16-31个字节inode为1,name是'..'  **/

```

 - 对inod块字段一一说明：
1. i_mode:表示文件类型和属性(rwx位)，这个初始化为：S_IFDIR + 0755，目录且权限是0755。其中各个比特位的意义是，0-2:其他人权限，3-5:组内权限，6-8:宿主权限，9-11:执行时权限，12-15:文件的类型（包括FIFO文件，字符设备文件，目录文件，块设备文件，常规文件）
2. i_uid:表示文件宿主的用户id，初始化为：执行mkfs.minix命令的用户id。
3. i_size:表示文件长度，初始化为:16*2=32，因为初始化的时候，inode表示一个目录，同时目录中有两个目录项分别是'.','..'，而一个目录需要16个字节来存储。
4. i_mtime:表示修改时间，从1970.1.1:0开始到执行初始化时候的秒数。初始化为：执行mkfs.minix的执行时间。
5. i_gid:表示文件宿主组id，初始化为：执行mkfs.minix命令用户所在所在组id，但是这个字段长度是char可能被截断。
6. i_nlinks:表示连接数，初始化为2，因为初始时候有两个目录项，都指向这个inode，所以初始的时候是2。
7. i_zone[9]:表示文件所占用磁盘上逻辑块号数组，zone[0]~zone[6]是直接逻辑块号 zone[7]一次间接块号 zone[8]二次间接块号 如果是设备文件则zone[0]指的是设备号。初始化为：在没有坏块的情况下,i_zone[0]=s_firstdatazone，首先这是一个目录文件，所以zone[0]是设备块号。
8. 说明：整个初始化过程不存的则数据块将被清0，仅仅设置了inode位图逻辑块位图，还有第一个inode指向逻辑块的内容被设置为1。

 - 对目录项块字段一一说明

```

## 目录项结构体

include/linux/fs.h
#define NAME_LEN 14
#define ROOT_INO 1

struct dir_entry {
	unsigned short inode;
	char name[NAME_LEN];
};

```
1. inode:表示这个目录项所指向的inode号。
2. name:表示目录的名字，最长14个字符
## 初始化一个mini1.0文件系统进行分析
本节通过初始化一个文件系统，查看文件中的数据并还原其中的数据结构。
 - 初始使用的工具

```

## 查看工具版本

$ mkfs.minix -V
mkfs.minix，来自 util-linux 2.30.1

```
- 初始化一个文件系统的过程

```

## 生成一个64M的文件

$ dd if=/dev/zero of=64M.img bs=512 count=131072
记录了131072+0 的读入
记录了131072+0 的写出
67108864 bytes (67 MB, 64 MiB) copied, 0.278518 s, 241 MB/s

## 这个版本的mkfs默认是创建minix2的fs，添加-n来创建minix1.0的fs

$ date && mkfs.minix -1 -n 14 64M.img
2017年 12月 07日 星期四 01:30:06 CST
21856 inodes
65535 blocks
Firstdatazone=696 (696)
Zonesize=1024
Maxsize=268966912

```
- 查看文件系统内容，并逐一分析

```

## 查看文件中的信息

$ hexdump 64M.img
0000000 0000 0000 0000 0000 0000 0000 0000 0000
*
0000400 5560 ffff 0003 0008 02b8 0000 1c00 1008
0000410 137f 0001 0000 0000 0000 0000 0000 0000
0000420 0000 0000 0000 0000 0000 0000 0000 0000
*
0000800 0003 0000 0000 0000 0000 0000 0000 0000
0000810 0000 0000 0000 0000 0000 0000 0000 0000
*
00012a0 0000 0000 0000 0000 0000 0000 fffe ffff
00012b0 ffff ffff ffff ffff ffff ffff ffff ffff
*
0001400 0003 0000 0000 0000 0000 0000 0000 0000
0001410 0000 0000 0000 0000 0000 0000 0000 0000
*
00033a0 0000 0000 0000 0000 ff00 ffff ffff ffff
00033b0 ffff ffff ffff ffff ffff ffff ffff ffff
*
0003400 41ed 03e8 0020 0000 291e 5a28 02e8 02b8
0003410 0000 0000 0000 0000 0000 0000 0000 0000
*
00ae000 0001 002e 0000 0000 0000 0000 0000 0000
00ae010 0001 2e2e 0000 0000 0000 0000 0000 0000
00ae020 0000 0000 0000 0000 0000 0000 0000 0000
*
4000000

```

首先根据第二节的知识，结合dump出的数据，我们知道一个minix1.0文件系统的分布图：
 
| 引导块1KB | 超级快1KB | inode map 3KB | 逻辑块位图 8KB | inode块 | .. |数据块 |
| ---|---|---|---|---|---|---
| 0~0x3ff | 0x400~0x7ff| 0x800~13FF|1400~33FF | 3400~3ff4 | ..|0xae000~end |
| 第0块 | 第1块 | 第2块 | 第5块 | 第13块 | ..| 第696块 |

 - 我们根据数据对超级快结构来翻译一下，超级快在引导区后面0x400~0x7ff:
1. s_ninodes=0x5560=21856，由于入参没有指定inode个数，则为65535/3=21845，硬盘中存储的inode大小是16B，则每个块可以存放1024/16=64个inode，那么(21845+64-1)& ~(64-1)=101010110000000b=0x5560
2. s_nzones=0xffff=65535，本次是一个64MB的文件64MB/1024=65536,而我们的s_nzones是一个short型最大表示65535，所以大于65535的统一设置为65535，可以dd的counts少4个块测试下，则这个字段会是0xfffe个。
3. s_imap_blocks=0x3=3[一个块最多有8192个位]，也就是21856需要用3个块来表示
4. s_zmap_blocks=0x8=8，也就是数据块需要8个逻辑块来表示
5. s_firstdatazone=0x2b8=696，咱们的块的计数是从第0块开始计数的，这个表示第696块。
6. s_log_zone_size=0
7. s_max_size=0x10081c00=268966912，见第一节说明。
8. s_magic=0x137f
9. s_state=0x1=1，这是这个mkfs里面增加的一个字段在linux0.11的minix1.0文件系统中没有这个字段的。
 - 计算出超级快以后，可以知道文件系统的分布图，下面对其他的块进行解释:
     - inode map 3KB说明：
        - 在一个字节中，低位表示小号的inode块，高位表大号的inode块
        - 第一个字节是3，也就是00000011，第0位是1表示无效，第1位为1表示第一个inode节点被占用，mkfs.minix时候建立的第一个inode，这个inode的内容下面分析dump出的inode字段时候时候再说明。
        - inode节点21856个，表示需要21856个bit位，其他多于的设置为1,从数据可以看出00012ac字节的第0位为0，表示最后一个没有被占用的bit，则可以得出（0x00012ab-0x800+1）*8-1(第0位不用)+1(第0x00012ac的第0位是0)=21856
     - 逻辑块 8KB说明:
        - 每个字节中，低位表示小号的数据块。
        - map中第0位不使用。
        - map中带1位标记为1表示使用，这个位指向的就是s_firstdatazone所代表的块号。
        - 从数据中计算出逻辑块位图的个数为：（0x00033a8-0x0001400+1）*8-1(第0位不是用)=64839
        - 65535-（s_firstdatazone+1)+1=64839，这样算出位图与块数一致，开始是696块,说明有670块。
- 根据数据结合inode块结构来翻译一下:    
    - inode中放入了第一个目录的信息
    - inode块的起始位置是逻辑块位图最后一个块的下一个块。


```

## 查看当前执行命令用户的uid和gid

$ id
uid=1000(deviosyan) gid=1000(deviosyan) 组=1000(deviosyan),4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),118(lpadmin),128(sambashare)

## 计算的unix时间的转换

$ date -d @1512581406
2017年 12月 07日 星期四 01:30:06 CST

unsigned short i_mode; //41ed=04000+0755
                       // 初始化为：S_IFDIR + 0755
                       //表示是一个目录，且权限是0755
unsigned short i_uid;  //文件宿主的用户id
                       //初始化为：执行mkfs.minix命令的用户id
                       //03e8=1000
unsigned long i_size;  //文件长度
                       //0x0020=32
                       //初始化为:16*2=32
unsigned long i_mtime; //修改时间[从1970.1.1:0开始的秒数]
                       //0x5a28291e=1512581406，转化成正常时间与命令执行的时间相同。  //取当前系统时间[就是mkfs.minix命令执行的时间]
	
unsigned char i_gid;  //文件宿主组id
                      //e8=232与实际有出入 我理解组id是按照char存储的所以被截断的3e8截断后就是e8
	                  //初始化为：如果i_uid存在则为i_uid所在组
unsigned char i_nlinks; //连接数
                        //初始化是2
                        //表示'.'和'..'这两个目录的链接
unsigned short i_zone[9];//0x2b8=696,第一个数据区的逻辑块，也就是这个inode的目录内容记录在696这个块上。

```

- 根据第一个逻辑块中的数据结合目录结构来翻译一下第一inode指向的内容:    


```

//第一个inode数据放在数据区的第一个块
00ae000:存储的第一个目录信息
struct dir_entry {
	unsigned short inode; //初始化为:1,指向第一个inode节点
	char name[NAME_LEN];  //初始化为："0x002e 0000"
	                      //查看ascii码表，0x002e代表的是 '.'，就是本目录。
    
};
00ae010:存储的第二个目录信息与第一个起始地址相差16个字节
struct dir_entry {
	unsigned short inode; //初始化为:1,指向第一个inode节点
	char name[NAME_LEN];  //初始化为："0x002e 0x002e 0000"
	                      //那代表的就是'..'，就是父目录也是本目录
    
};
也就是说，在跟目录中cd .和 cd ..都会在根目录
//验证操作系统验证
$ cd /
$ pwd
/
$ cd .
$ pwd
/
$ cd ..
$ pwd
/
//说明根目录的父目录就是本身

```
## 小结
这个系列文章期望从用户使用文件系统角度，来对minix1.0进行分析。本文描述了一个干净的文件系统的生成后的样子，后续会继续从操作层面继续分析mount文件系统，umount文件系统，新增文件，操作文件(读,写,删除,关闭文件,执行一个文件）。从而详细的展示一个文件系统的生命周期。

## 参考资料

 - mkfs.minix代码 https://www.kernel.org/pub/linux/utils/util-linux/v2.30/util-linux-2.30.1.tar.gz
