MKSHELL=bash
# easy way to terminate build process if no mkfile.rc is present
<| cat mkfile.rc

build:V: gcc-check hex

ARDUINO_CORE_DIR = $ARDUINO_PATH/hardware/arduino/cores/arduino
ARDUINO_LIBS_DIR = $ARDUINO_PATH/libraries

PROJECT_NAME = `{basename `pwd`}
BUILDDIR = build

INCLUDE = -I$ARDUINO_CORE_DIR -I. `{for lib in $ARDUINO_LIBS; do echo -I$ARDUINO_LIBS_DIR/$lib; done}

BOARDS_DB = $ARDUINO_PATH/hardware/arduino/boards.txt
F_CPU    = `{sed -nr "s/^$BOARD\.build\.f_cpu=(.+)/\1/p"         $BOARDS_DB }
MCU      = `{sed -nr "s/^$BOARD\.build\.mcu=(.+)/\1/p"           $BOARDS_DB }
PROTOCOL = `{sed -nr "s/^$BOARD\.upload\.protocol=(.+)/\1/p"     $BOARDS_DB }
MAX_SIZE = `{sed -nr "s/^$BOARD\.upload\.maximum_size=(.+)/\1/p" $BOARDS_DB }
SPEED    = `{sed -nr "s/^$BOARD\.upload\.speed=(.+)/\1/p"        $BOARDS_DB }

AVRDUDE_FLAGS = -C $ARDUINO_PATH/hardware/tools/avrdude.conf \
                -c $PROTOCOL \
                -p $MCU \
                -b $SPEED \
                -P $TTYDEV \
                -U flash:w:$BUILDDIR/$PROJECT_NAME.hex:i \

GENERIC_CFLAGS = -Os -mmcu=$MCU
# do -w really are necessary here?
CFLAGS         = $GENERIC_CFLAGS \
               -c \
               -g \
               -w \
               -ffunction-sections \
               -fdata-sections \
               -funsigned-char \
               -funsigned-bitfields \
               -fpack-struct \
               -fshort-enums \
               -DF_CPU=$F_CPU \
               -DARDUINO=$ARDUINO_VER

CXXFLAGS       = $CFLAGS -fno-exceptions
ELF_CFLAGS     = $GENERIC_CFLAGS -Wl,--gc-section -Wl,-O1 -lm

CC      = avr-gcc
CXX     = avr-g++
AR      = avr-ar
OBJCOPY = avr-objcopy
SIZE    = avr-size
AVRDUDE = avrdude

# double inclusion allows to override internal variables if necessary
<mkfile.rc

ARDUINO_CORE_OBJ = `{ ls $ARDUINO_CORE_DIR | sed -nr "s?(.*)\.(cpp|c)\$?$BUILDDIR/core/\1.o?p"}
ARDUINO_LIBS_BUILDDIRS = `{for lib in $ARDUINO_LIBS; do echo $BUILDDIR/lib/$lib; echo $BUILDDIR/lib/$lib/utility; done}
ARDUINO_LIBS_OBJ = `{ \
	for lib in $ARDUINO_LIBS; do \
		ls $ARDUINO_LIBS_DIR/$lib/*.c* $ARDUINO_LIBS_DIR/$lib/utility/*.c* 2> /dev/null | \
			sed -nr "s?$ARDUINO_LIBS_DIR/(.*)\.(cpp|c)\$?$BUILDDIR/lib/\1.o?p"; \
	done}

SKETCH_PDE_CXX_SRC = `{ ls *.pde 2> /dev/null | sed -r "s|(.+)\.pde|$BUILDDIR/sketch/\1.cpp|" }
SKETCH_OBJ         = `{ ls *.pde *.c *.cpp 2> /dev/null | sed -r "s|^(.+)\.[^\.]+\$|$BUILDDIR/sketch/\1.o|" }

$BUILDDIR/core $ARDUINO_LIBS_BUILDDIRS $BUILDDIR/sketch $BUILDDIR/::
	mkdir -p $target

gcc-check:VQ:
    if [[ "$($CC -v 2>&1 | tail -n1 | cut -f 3 -d " " | cut -c1-3)" > "4.3" && -n $(echo "$BOARD" | grep mega) && -z "$NO_GCC_CHECK" ]] ; then
        echo "your version of gcc is known to produce broken code for mega and mega2560 boards"
        echo "please consider downgrade of your gcc or applying the patch"
        echo 
        echo "for further information check this links"
        echo "http://gcc.gnu.org/bugzilla/show_bug.cgi?id=45263"
        echo "http://andybrown.me.uk/ws/2010/10/24/the-major-global-constructor-bug-in-avr-gcc/"
        echo "http://www.arduino.cc/cgi-bin/yabb2/YaBB.pl?num=1276727004/15"
        echo
        echo "to disable this check add NO_GCC_CHECK=1 to your mkfile.rc"
        exit 1
    fi

#core
arduino_core:V: $BUILDDIR/core $BUILDDIR/core.a

$BUILDDIR/core.a: $ARDUINO_CORE_OBJ
	$AR rcs $BUILDDIR/core.a $BUILDDIR/core/*.o

$BUILDDIR/core/%.o:: $ARDUINO_CORE_DIR/%.c
	$CC $CFLAGS $prereq -o $target -I$ARDUINO_CORE_DIR

$BUILDDIR/core/%.o:: $ARDUINO_CORE_DIR/%.cpp
	$CXX $CXXFLAGS $prereq -o $target -I$ARDUINO_CORE_DIR

#libs
arduino_libs:VQ: $ARDUINO_LIBS_BUILDDIRS $ARDUINO_LIBS_OBJ 
    # dummy in case of no libs
    true

$BUILDDIR/lib/%.o:: $ARDUINO_LIBS_DIR/%.c
	$CC $CFLAGS $prereq -o $target -I$ARDUINO_LIBS_DIR/`echo $stem | cut -d '/' -f 1`/utility $INCLUDE

$BUILDDIR/lib/%.o:: $ARDUINO_LIBS_DIR/%.cpp
	$CXX $CXXFLAGS $prereq -o $target -I$ARDUINO_LIBS_DIR/`echo $stem | cut -d '/' -f 1`/utility $INCLUDE

#sketch
sketch:V: $BUILDDIR/sketch $SKETCH_OBJ

$BUILDDIR/sketch/%.cpp:: &.pde
	echo '#include "WProgram.h"' > $target
	cat $prereq >> $target

$BUILDDIR/sketch/%.o:: $BUILDDIR/sketch/%.cpp
	$CXX $CXXFLAGS $prereq -o $target $INCLUDE

$BUILDDIR/sketch/%.o:: &.c
	$CC $CFLAGS $prereq -o $target $INCLUDE

$BUILDDIR/sketch/%.o:: &.cpp
	$CC $CFLAGS $prereq -o $target $INCLUDE

#hex
hex:V: $BUILDDIR/$PROJECT_NAME.hex checksize

$BUILDDIR/$PROJECT_NAME.elf:: arduino_core arduino_libs sketch
	$CC $ELF_CFLAGS -o $target \
		$ARDUINO_LIBS_OBJ $SKETCH_OBJ $BUILDDIR/core.a \
		-L$BUILDDIR

$BUILDDIR/$PROJECT_NAME.hex:: $BUILDDIR/$PROJECT_NAME.elf
	$OBJCOPY -O ihex -j .eeprom --set-section-flags=.eeprom=alloc,load \
		--no-change-warnings --change-section-lma .eeprom=0 \
		$prereq $BUILDDIR/$PROJECT_NAME.eep
	
	$OBJCOPY -O ihex -R .eeprom $prereq $target

checksize:VQ: $BUILDDIR/$PROJECT_NAME.hex
	size=$($SIZE $prereq | tail -n1 | cut -f2)
	if [ $MAX_SIZE -lt $size ]; then
		echo "hex size ($size bytes) exceeds size limit ($MAX_SIZE)"
		exit 1
	else
		echo "hex size: $size bytes, $(printf '%.2f%%' $(dc -e "10 k $size $MAX_SIZE 100 / / p")) used"
	fi

upload:VQ: hex
	stty -F $TTYDEV hupcl
	$AVRDUDE $AVRDUDE_FLAGS

nuke:V: clean
clean:V:
	rm -rf $BUILDDIR
