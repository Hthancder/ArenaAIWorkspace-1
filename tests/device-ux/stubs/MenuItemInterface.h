#pragma once
#include "globals.h"
#include <functional>
#include <vector>
struct Option { String label; std::function<void()> operation; };
constexpr int MENU_TYPE_SUBMENU = 1;
extern bool returnToMenu;
int loopOptions(std::vector<Option>&, int, const char*);
struct TftStub {
    void drawCircle(int, int, int, int) {}
    void drawWideLine(int,int,int,int,int,int,int) {}
};
extern TftStub tft;
class MenuItemInterface {
public:
    explicit MenuItemInterface(const char*) {}
    virtual ~MenuItemInterface() = default;
    virtual void optionsMenu() = 0;
    virtual void drawIcon(float) = 0;
    virtual bool hasTheme() = 0;
    virtual const String& themePath() = 0;
protected:
    int iconCenterX = 50, iconCenterY = 50;
};
