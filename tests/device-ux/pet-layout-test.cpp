#include <cassert>
#include <iostream>
#include "modules/pwnagotchi/pet_layout.h"
int main() {
    for (auto size : {std::pair<int,int>{284,240}, {240,284}, {320,240}, {240,320}}) {
        const int w=size.first, h=size.second, top=h/10, bottom=h*9/10;
        const auto p=petLayout(w,h,top,bottom);
        assert(p.left>=0 && p.left+p.width<=w && p.top>=top && p.top+p.height<p.phraseY);
        assert(p.phraseY+13<bottom && p.phraseWidth<=w && p.width==p.height);
    }
    std::cout << "Pet layout orientation regression tests passed\n";
}
