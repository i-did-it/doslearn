pcxview.exe: pcxview.obj .AUTODEPEND
	wlink name $@ format dos file $?

pcxview.obj: pcxview.asm
	wasm -bt=dos -0 -zz -fo=$@ $<

clean: .SYMBOLIC
	@IF EXISTS *.EXE DEL *.EXE
	@IF EXISTS *.OBJ DEL *.OBJ

