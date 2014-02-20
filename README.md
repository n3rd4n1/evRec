evRec
=====

A Mac OS X utility to capture, analyse, edit, replay, save, and load previously saved Mac OS X events (NSEvent).


Usage
-----

![pre-capture](http://n3rd4n1.github.io/images/screenshot/evRec/pre-capture.png)

Upon launching evRec, a window similar to the image above (minus the filter entries) will be shown. You can either open a previously saved file, or start capturing live events.

Before starting a new capture, you can modify the filter as desired. You can also specify the mode of filtering using the filter mode toggle button. (+) means capture events that match the filter, whereas (-) means discard events that match the filter.

You can then start capturing events by pushing the capture button (dark gray circle).

When evRec is started without administrator privileges, which means it can't capture events that require elevated privileges i.e. key events, an unlock button will be visible. Pushing this button will ask for an administrator's credential to elevate privileges which, when granted, will launch another evRec process with elevated privileges and close the current evRec process.


![on-capture](http://n3rd4n1.github.io/images/screenshot/evRec/on-capture.png)

The capture button will turn from dark gray circle to red circle which indicates that evRec is now capturing events. Pushing the capture button the second time will stop the capture session.


![post-capture](http://n3rd4n1.github.io/images/screenshot/evRec/post-capture.png)

When one or more events were captured, or when events from a file were successfully loaded, a window sheet will be presented. This sheet provides more information for each captured events by showing known event fields, as well as the raw bytes comprising the event. Editing of the event is possible only through the presented event fields.

The sheet also provides a playback button to replay all checked events.

Finally, you can save all checked events in a file. You can have multiple different files by saving different event combinations (checked events).

Go back to the capture window by pushing the close button.


Download
--------

[evRec-1.0.zip](http://n3rd4n1.github.io/bin/evRec-1.0.zip)


[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/n3rd4n1/evrec/trend.png)](https://bitdeli.com/free "Bitdeli Badge")

