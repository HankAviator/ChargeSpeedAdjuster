SKIPUNZIP=0
REPLACE=""
MODDIR=${0%/*}
echo " "
echo "*******************"
echo "- 手机信息"
echo "- SDK: $(getprop ro.build.version.sdk)"
echo "- 设备: $(getprop ro.fota.oem)"
echo "- 设备代号: $(getprop ro.product.device)"
echo "- 安卓版本: Android $(getprop ro.build.version.release)"
echo "*******************"

#检测是否读取到电流控制文件
if [ ! -f /sys/class/power_supply/battery/constant_charge_current ] && [ ! -f /sys/class/power_supply/battery/constant_charge_current_max ] && [ ! -f /sys/class/power_supply/battery/fast_charge_current ];
then
  echo "目标文件未找到！可自行寻找电流文件，修改代码！"
else
  echo "找到电流控制文件！模块生效！（大概）"
fi

#清理旧模块
rm -rf "/data/adb/modules/ChargeSA/"
rm -rf "/data/adb/modules/HeZheng/"

#检测是否读取到当前电量
if [ ! -f "/sys/class/power_supply/battery/capacity" ]; then
  echo "阶梯充电功能失效！满血充电正常！"
else
  echo "阶梯充电功能生效！满血充电正常！"
fi
sleep 1
echo "！！！请仔细阅读以下说明！！！"
echo "-------------------------------------"
echo "4.1版本更新如下："
echo "亮屏息屏均生效！"
echo "根据自己手机的温控文件生成只删除充电温控的温控！"
echo "若未删除温控,则只删除充电温控！"
echo "若已经删除温控,则不更改温控,只控制充电,但有可能会无法安装!"
echo "若修改过但未删除温控,则有可能使修改过的温控失效!"
echo "官改可能不生效!"
echo "类原生估计也不行!"
echo "尝试适配ksu!"
echo "借鉴了很多大佬的代码,感谢!"
echo "@鹤征(模块主要逻辑)@shadow3(修改温控思路)@嘟嘟斯基(解密温控)"
echo "-------------------------------------"
sleep 3
#检测是否为小米手机
var_device="`getprop ro.fota.oem`"
if [ "$var_device" != "Xiaomi" ]; then
  abort "此模块只适用于小米设备！"
else
  echo "installing..."
  sleep 1
  # permission
  chmod a+x $MODPATH/miui-thermal
  chmod a+x $MODPATH/thermal-bat
  sh $MODPATH/edit.sh >/dev/null 2>&1
  echo "充电温控删除完毕，请重启！"
fi
