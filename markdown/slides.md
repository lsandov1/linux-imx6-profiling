# Linux `i.MX6` Profiling

## What is Profiling?

* Record CPU execution and get statistics from it

* When do I need to profile the system?
    * Is my system running slow?
    * Are system resources (i.e. memory, CPU, ethernet, etc.) overloaded (> 70 %)?
    * Is SW using HW accelerators?

* Commonly done **after** the developing phase

    > Premature optimization is the root of all evil (or at least most of it) in programming. 
    > Donald Knuth

* **Measuring** is another common term for profiling

* **Tracing** is a more general task: Record the CPU execution

* From the tracing log/info, there are (profiling) tools to generate (profiling) data

## Profiling the Kernel boot-up

* `grabserial` is a possible solution (takes every line coming from the serial line and
  time-stamp it) where nothing is change on the system

* A better solution indicate the kernel to show these times with the kernel command
  line parameter `printk.time=1`

~~~~
> setenv mmcargs setenv bootargs console=ttymxc0,115200 root=/dev/mmcblk0p2 rootwait rw printk.time=1
> save
> boot
~~~~

* To know the amount of time it takes to load all the individual non-core drivers in the
  kernel

~~~~
> setenv mmcargs setenv bootargs console=ttymxc0,115200 root=/dev/mmcblk0p2 rootwait rw printk.time=1 initcall_debug
> save
> boot
~~~~

* What is the task consuming most time?

~~~~
.
.
.
[    3.916876]   #1: imx-hdmi-soc
[   11.901625] kjournald starting.  Commit interval 5 seconds
.
.
~~~~

* How can be reduce the *big* delta?

## Lab 1: Fasten boot through filesystem type

* Convert the rootfs system from `ext3` to `ext2` and measure times again

* How fast is the boot this time?

## Profilers

* There are many tools to profile either kernel-space, user-space or both

* We will focus on three:
    1. `strace` for kernel profiling
    2. `ltrace` for library profiling
    3. `OProfile` for system and application profiling


## Image Setup

* We need to include these some more debug tools (strace) into our `fsl-image-machine-test`

1. Layer Creation (jump this step if you already have a custom layer, just set the `LAYER_NAME` variable)

~~~~{.bash}
$LAYER_NAME=profiling
sources $: ./poky/scripts/yocto-layer create $LAYER_NAME
sources $: mkdir -p meta-$LAYER_NAME/recipes-fsl/images
~~~~

2. Image Creation

~~~~{.python}
sources $: gedit meta-$LAYER_NAME/recipes-fsl/images/fsl-image-machine-test-debug.bb
require recipes-fsl/images/fsl-image-machine-test.bb

# add debugging tools (gdb, strace)
EXTRA_IMAGE_FEATURES += "tools-debug"

# add ltrace tool (library tracing)
CORE_IMAGE_EXTRA_INSTALL += "ltrace"

# add your custom app
CORE_IMAGE_EXTRA_INSTALL += "<CUSTOM APP NAME>"
~~~~

3. Layer inclusion

~~~~{.python}
    sources $: gedit build/conf/bblayers.conf
# LAYER_CONF_VERSION is increased each time build/conf/bblayers.conf
# changes incompatibly
LCONF_VERSION = "6" 

BBPATH = "${TOPDIR}"
BSPDIR := "${@os.path.abspath(os.path.dirname(d.getVar('FILE', True)) + '/../..')}"

BBFILES ?= ""
BBLAYERS = " \ 
      ${BSPDIR}/sources/poky/meta \
      ${BSPDIR}/sources/poky/meta-yocto \
      \   
      ${BSPDIR}/sources/meta-openembedded/meta-oe \
      \   
      ${BSPDIR}/sources/meta-fsl-arm \
      ${BSPDIR}/sources/meta-fsl-arm-extra \
      ${BSPDIR}/sources/meta-fsl-demos \
      \   
      ${BSPDIR}/sources/meta-<LAYER_NAME> \
    "   
~~~~

4. Setup environment

~~~~{.bash}
$: source setup-environment build
~~~~

5. Final system image generation

~~~~{.bash}
build $: bitbake fsl-image-machine-test-debug
~~~~

6. Flash/Burn

~~~~{.bash}
build $: sudo umount /dev/sdb?
build $: SDCARD=tmp/deploy/images/imx6qsabresd/fsl-image-machine-test-debug-imx6qsabresd.sdcard
build $: sudo dd if=$SDCARD of=/dev/sdb bs=1M conv=fsync; sync
~~~~

## Kernel-space profiling: `strace`

* Trace system calls and signals. [`strace` site](http://linux.die.net/man/1/strace)

* Let's profile the unit test `mxc_v4l2_overlay.out' application (takes camera data and display on screen)

* Setup

~~~~{.bash}
$: CMD=/unit_tests/mxc_v4l2_overlay.out
$: PARAMS="-iw 1280 -ih 720 -it 0 -il 0 -ow 1280 -oh 720 -ot 0 -ol 0 -r 0 -t 5 -do 0 -fg -fr 30"
~~~~

* `strace` report

~~~~{.bash}
$: strace -c $CMD $PARAMS
~~~~

* What is the most costly system call? `ioctl` [call](http://man7.org/linux/man-pages/man2/ioctl.2.html)

* Detailed log: Relative timestamp upon entry to each system call

~~~~{.bash}
$: strace -r $CMD $PARAMS
~~~~

* Detailed log: Time spent in system calls

~~~~{.bash}
$: strace -T $CMD $PARAMS
~~~~

## Lab 2: `strace`

* Run `strace` with a `VPU` unit test

* Command to be run

~~~~{.bash}
/unit_tests/mxc_vpu_test.out -D "-i /unit_tests/akiyo.mp4 -f 0 -o akiyo.yuv"
~~~~

* Is the `ioctl` system call the most call this time?

## User-space profiling: `ltrace` (**NOT WORKING**)


* A library call tracer (pretty similar to `strace` but this tool reports libraries calls)
* Reminder: Libraries reside in user-space and device drivers reside in kernel-space

* `ltrace` report

~~~~{.bash}
$: ltrace -c $CMD $PARAMS
~~~~

* What is the most consuming library call?

## System profiler: `Oprofile`

* OProfile is a system-wide profiler for Linux systems, capable of profiling all running code at low overhead

* Features:

    * **Unobtrusive**: no special recompilations, wrapper libraries or the like necessary. Even debug symbols (`-g` option to `gcc`)
      are not necessary 
    * **System-wide profiling**: All code running on the system is profiled, enabling analysis of system performance
    * **Single process profiling**:
    * **Low overhead**: OProfile has a typical overhead of 1-8%
    * **Post-profile analysis**

* [Site](http://oprofile.sourceforge.net/news/)


## `Oprofile` Setup

* We need to enable a kernel with `Oprofile`. Two ways:

    1. Clean: Including the new kernel configuration in the custom layer
    2. Dirty: Opening the `menuconfig` of the kernel through `bitbake`, compiling and
              flashing on the first partition
        

* Let's do the second approach

~~~~{.bash}
build $: bitbake -c menuconfig linux-imx

General Setup --->
    [*] Profiling Support
    <*> OProfile system profiling
~~~~

* Check the new `.config`

~~~~{.bash}
build $: cat tmp/work/imx6qsabresd-poky-linux-gnueabi/linux-imx/3.10.17-r0/git/.config | grep OPROFILE
CONFIG_OPROFILE=y
CONFIG_HAVE_OPROFILE=y
~~~~

* Compile

~~~~{.bash}
build $: bitbake linux-imx
~~~~

* Connect the SD to the PC and copy the new image

~~~~{.bash}
build $: cp tmp/deploy/images/imx6qsabresd/uImage /media/<BOOT PARTITION>
build $: sync; sudo umount /dev/sdb?
~~~~

* Power on the board and stop boot: Currently, `OProfile` can only work
with **one** core, otherwise kernel will crash

~~~~
> setenv mmcargs ${mmcargs} maxcpus=1
> boot
~~~~

## `OProfile` Usage

* Make sure you have all necessary setup needed to launch the application

~~~~{.bash}
root@imx6qsabresd:~# CMD=/unit_tests/mxc_v4l2_overlay.out
root@imx6qsabresd:~# PARAMS="-iw 1280 -ih 720 -it 0 -il 0 -ow 1280 -oh 720 -ot 0 -ol 0 -r 0 -t 5 -do 0 -fg -fr 30"
~~~~

* Start up the profiler

~~~~{.bash}
root@imx6qsabresd:~# opcontrol --no-vmlinux
root@imx6qsabresd:~# opcontrol --start
~~~~

* Launch any application

~~~~{.bash}
root@imx6qsabresd:~# $CMD $PARAMS
~~~~

* Stop the profiler

~~~~{.bash}
root@imx6qsabresd:~# opcontrol --stop
~~~~

* Let's generate a profiling summary of a specific binary (Only useful when image included 
`EXTRA_IMAGE_FEATURES += "dbg-pkgs"`)

~~~~{.bash}
root@imx6qsabresd:~# opreport -l $CMD
~~~~

* System-wide report

~~~~{.bash}
root@imx6qsabresd:~#  opreport
~~~~

* System-wide symbol summary including per-application libraries (Only useful when image included 
`EXTRA_IMAGE_FEATURES += "dbg-pkgs"`)

~~~~{.bash}
opreport --symbols --image-path=/lib/modules/3.10.17-1.0.1_ga+gdac46dc/kernel/
~~~~

* Many more interesting examples on the OProfile [site](http://oprofile.sourceforge.net/examples/)


## Lab 3: `Oprofile` the custom app

OProfile a custom application create a report

To stress the system, running `n` times with

~~~~{.bash}
APP=./helloworld
for i in `seq 1 100`; $APP; done
~~~~
