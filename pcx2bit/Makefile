pcx2bit.exe: pcx2bit.obj .AUTODEPEND
	wlink name $@ format dos file $?

pcx2bit.obj: pcx2bit.asm
	wasm -0 -bt=dos -fo=$@ $<

clean: .SYMBOLIC
	@IF EXISTS *.exe DEL *.exe
	@IF EXISTS *.obj DEL *.obj
