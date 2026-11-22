#pragma once
#include <cstddef>
#include <cstdint>
using i2s_chan_handle_t = void*;
#define I2S_NUM_0 0
#define I2S_ROLE_MASTER 1
#define I2S_DATA_BIT_WIDTH_16BIT 16
#define I2S_SLOT_MODE_STEREO 2
#define I2S_GPIO_UNUSED -1
#define GPIO_NUM_5 5
#define GPIO_NUM_15 15
#define GPIO_NUM_16 16
#define GPIO_NUM_6 6
#define ESP_OK 0
struct i2s_chan_config_t { int port; int role; int dma_desc_num; int dma_frame_num; };
struct clock_config { int sample_rate_hz; };
struct slot_config { int width; int channels; bool bit_shift; };
struct gpio_config { int mclk, bclk, ws, dout, din; struct { bool mclk_inv, bclk_inv, ws_inv; } invert_flags; };
struct i2s_std_config_t { clock_config clk_cfg; slot_config slot_cfg; gpio_config gpio_cfg; };
#define I2S_CHANNEL_DEFAULT_CONFIG(p,r) i2s_chan_config_t{p,r,0,0}
#define I2S_STD_CLK_DEFAULT_CONFIG(hz) clock_config{hz}
#define I2S_STD_MSB_SLOT_DEFAULT_CONFIG(w,c) slot_config{w,c,false}
int i2s_new_channel(const i2s_chan_config_t*, i2s_chan_handle_t*, void*);
int i2s_channel_init_std_mode(i2s_chan_handle_t,const i2s_std_config_t*);
int i2s_channel_enable(i2s_chan_handle_t);
int i2s_channel_write(i2s_chan_handle_t,const void*,size_t,size_t*,unsigned);
int i2s_channel_disable(i2s_chan_handle_t);
int i2s_del_channel(i2s_chan_handle_t);
