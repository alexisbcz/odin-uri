// Example basic shows the smallest useful mylib program. Run it with `odin run examples/basic`.
package main

import mylib "../.."
import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
	line, err := mylib.repeat("na", 8)
	if err != nil {
		fmt.eprintln("repeat failed:", err)
		os.exit(1)
	}
	defer delete(line)
	fmt.println(line, "batman")

	tally: mylib.Tally
	mylib.tally_init(&tally)
	defer mylib.tally_destroy(&tally)

	text := "the cat saw the dog"
	for word in strings.fields_iterator(&text) {
		_ = mylib.tally_add(&tally, word)
	}
	fmt.println("the:", mylib.tally_count(&tally, "the"))
}
