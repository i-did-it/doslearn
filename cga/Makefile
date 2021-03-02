cgapix.exe: cgapix.obj .AUTODEPEND
	wlink name $@ format dos file $?

cgapix.obj: cgapix.asm
	wasm -0 -bt=dos -zz -fo=$@ $<

clean: .SYMBOLIC
	find . -name "*.exe" -delete -maxdepth 1
	find . -name "*.obj" -delete -maxdepth 1
