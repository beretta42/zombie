all: zombie ns cdig


bounce.h: bounce.s
	lwasm -f raw -o bounce bounce.s
	xxd -i bounce > bounce.h

zombie: zombie.c bounce.h
	gcc -o zombie zombie.c -ledit

ns: ns.c
	gcc -o ns ns.c

cdig: cdig.c
	gcc -o cdig cdig.c

clean:
	rm -f *~ zombie bounce bounce.h ns cdig
