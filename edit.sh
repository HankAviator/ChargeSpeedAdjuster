#!/system/bin/sh
MODDIR=${0%/*}

#复制温控文件（加密）
cp -r /vendor/etc/thermal-*.conf $MODDIR/temp/origin_en
cp -r /data/vendor/thermal/config/thermal-*.conf $MODDIR/temp/origin_en
cp -r /odm/etc/thermal-*.conf $MODDIR/temp/origin_en
cp -r /system/etc/thermal-*.conf $MODDIR/temp/origin_en
#判断$MODDIR/temp/origin_en是否为空
if [ ! -n "$(ls -A $MODDIR/temp/origin_en)" ]; then
    abort "温控文件未找到！"
fi
#解密温控文件
$MODDIR/miui-thermal -d=true -i=$MODDIR/temp/origin_en -o=$MODDIR/temp/origin_de
#修改温控文件
$MODDIR/thermal-bat $MODDIR/temp/origin_de/ $MODDIR/temp/edited_de/
#修改温控权限
chattr -R -i /data/vendor/thermal/config/
chmod -R 771 /data/vendor/thermal/config
#加密温控文件
$MODDIR/miui-thermal -d=false -i=$MODDIR/temp/edited_de -o=$MODDIR/temp/edited_en
#复制到对应文件夹
cp -rf $MODDIR/temp/edited_en/* $MODDIR/system/vendor/etc/
cp -rf $MODDIR/temp/edited_en/* /data/vendor/thermal/config/
#删除临时文件
rm -rf $MODDIR/temp