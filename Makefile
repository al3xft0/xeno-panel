SDK     := iphoneos
MIN     := 16.0
OUT     := FreeFirePanel.dylib
DUMP    := OffsetsDump.dylib
SRC     := src/Panel.mm src/Menu.mm
FLAGS   := -std=c++17 -fobjc-arc -O2 -fvisibility=hidden \
           -mios-version-min=$(MIN) -Isrc \
           -framework UIKit -framework QuartzCore -framework CoreGraphics

all: $(OUT)

arm64: $(SRC) src/*.h
	xcrun -sdk $(SDK) clang++ -arch arm64 $(FLAGS) -dynamiclib \
		-install_name @executable_path/Frameworks/$(OUT) -o $(OUT).arm64 $(SRC)

arm64e: $(SRC) src/*.h
	xcrun -sdk $(SDK) clang++ -arch arm64e $(FLAGS) -dynamiclib \
		-install_name @executable_path/Frameworks/$(OUT) -o $(OUT).arm64e $(SRC)

$(OUT): arm64 arm64e
	lipo -create -output $(OUT) $(OUT).arm64 $(OUT).arm64e
	@rm -f $(OUT).arm64 $(OUT).arm64e
	@lipo -info $(OUT)

dump: src/Dump.mm src/*.h
	xcrun -sdk $(SDK) clang++ -arch arm64 $(FLAGS) -dynamiclib \
		-install_name @executable_path/Frameworks/$(DUMP) -o $(DUMP).arm64 src/Dump.mm
	xcrun -sdk $(SDK) clang++ -arch arm64e $(FLAGS) -dynamiclib \
		-install_name @executable_path/Frameworks/$(DUMP) -o $(DUMP).arm64e src/Dump.mm
	lipo -create -output $(DUMP) $(DUMP).arm64 $(DUMP).arm64e
	@rm -f $(DUMP).arm64 $(DUMP).arm64e

clean:
	rm -f $(OUT) $(OUT).* $(DUMP) $(DUMP).*

.PHONY: all arm64 arm64e dump clean
