cmake -S vendor/sdl3 -B vendor/sdl3/build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build vendor/sdl3/build --parallel
