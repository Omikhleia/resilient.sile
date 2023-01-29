The printer illustrations come from public domain sources.

They were cropped and optimized for size. And just because I never remember how to
perform these optimizations, here is for the record what I use.

For PNG images

```
sudo apt install optipng
sudo apt install pngnq

pngnq -f -v -s1 file.png

optipng -o7 -full -strip all file.png
```

For JPEG images

```
sudo apt install jpegoptim

jpegoptim --strip-all file.jpg or for 90% quality jpegoptim -m90 --strip-all file.jpg
```
