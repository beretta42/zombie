all: zombie ns cdig


bounce.h: bounce.s bounce09.s
	lwasm -f raw -o bounce bounce.s
	lwasm -f raw -o bounce09 bounce09.s
	xxd -i bounce > bounce.h
	xxd -i bounce09 >> bounce.h

zombie: zombie.c bounce.h
	gcc -o zombie zombie.c -lreadline

ns: ns.c
	gcc -o ns ns.c

cdig: cdig.c
	gcc -o cdig cdig.c

clean:
	rm -f *~ zombie bounce bounce.h ns cdig
