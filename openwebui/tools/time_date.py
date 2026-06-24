"""
title: Time & Date
author: local
version: 0.1.0
license: MIT
description: Returns the current date/time so the model isn't anchored to its training cutoff.
"""
from datetime import datetime


class Tools:
    def __init__(self):
        pass

    def get_current_datetime(self) -> str:
        """
        Get the current local date and time. Call this whenever the user asks about
        the current date, time, day of week, or anything relative to "now" / "today".
        :return: The current date and time as a human-readable string with timezone.
        """
        now = datetime.now().astimezone()
        return now.strftime("%Y-%m-%d %H:%M:%S %Z — %A")
